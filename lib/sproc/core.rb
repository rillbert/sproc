# frozen_string_literal: true

require 'shellwords'
require 'open3'

module SProc
  # Defines the shell under which to invoke the sub-process
  module ShellType
    SHELL_TYPES = [
      # Start the process without any shell
      NONE = 0,
      # Will create a 'bash' instance and run the subprocess
      # within that instance.
      BASH = 1
    ].freeze
  end

  # The possible states of this subprocess
  module ExecutionState
    NOT_STARTED = 0
    RUNNING = 1
    ABORTED = 2
    COMPLETED = 3
    FAILED_TO_START = 4
  end

  # Represents queryable info about the task run by this SubProcess
  TaskInfo = Struct.new(
    :cmd_str, # the invokation string used to start the process
    :exception, # the exception terminating the process (nil if everything ok)
    :wall_time, # the time (in s) between start and completion of the process
    :process_status, # the ProcessStatus object (see Ruby docs)
    :popen_thread, # the thread created by the popen call, nil before started
    :stdout, # a String containing all output from the process' stdout
    :stderr # a String containing all output from the process' stderr
  )

  # Execute a command in a subprocess, either synchronuously or asyncronously.
  class SProc
    # support a class-wise logger instance
    @logger = nil
    class << self
      attr_accessor :logger
    end

    def logger
      self.class.logger
    end

    include ShellType
    include ExecutionState

    # prepare to run a sub process
    # @param type            the ShellType used to run the process within
    # @param stdout_callback a callback that will receive all stdout output
    #                        from the process as it is running (default nil)
    # @param stderr_callback a callback that will receive all stderr output
    #                        from the process as it is running (default nil)
    # @param env             a hash containing key/value pairs of strings that
    #                        set the environment variable 'key' to 'value'. If value
    #                        is nil, that env variable is unset
    #
    # example callback signature: def my_stdout_cb(line)
    def initialize(type = ShellType::NONE, stdout_callback: nil,
                   stderr_callback: nil, env: {})
      @run_opts = {
        type: type,
        stdout_callback: stdout_callback,
        stderr_callback: stderr_callback
      }
      @runner = TaskRunner.new(@run_opts)
      @execution_thread = nil
      @env = env
    end

    # Return the execution state of this SubProcess. Note that it is not
    # identical with the life-cycle of the underlying ProcessStatus object
    #
    # @return current ExecutionState
    def execution_state
      return ExecutionState::NOT_STARTED if @execution_thread.nil?

      # Count this SubProcess as running as long as the thread
      # that executes it is alive (this includes book keeping
      # chores within this class as well)
      return ExecutionState::RUNNING if @execution_thread.alive?

      status = task_info[:process_status]

      # an execution thread that has run but not generated a task_info
      # means that we tried to start a process but failed
      return ExecutionState::FAILED_TO_START if status.nil?

      # a process can terminate for different reasons:
      # - its done
      # - an uncaught exception-
      # - an uncaught signal

      # this should take care of uncaught signals
      return ExecutionState::ABORTED if status.signaled?

      # If the process completed (either successfully or not)
      return ExecutionState::COMPLETED if status.exited?

      # We don't currently handle a process that has been stopped...
      raise NotImplementedError("Unhandled process 'stopped' status!") if status.stopped?

      # We should never come here
      raise RuntimeError("Unhandled process status: #{status.inspect}")
    end

    # Start the sub-process and block until it has completed.
    #
    #
    # @cmd    the command to execute
    # @args   an array with all arguments to the cmd
    # @opts   a hash with options that influence the spawned process
    #         the supported options are: chdir umask unsetenv_others
    #         See Process.spawn for definitions
    #
    # @return this SubProcess instance
    def exec_sync(cmd, *args, **opts)
      exec(true, @env, cmd, *args, **opts)
    end

    # Start the process non-blocking. Use one of the wait... methods
    # to later block on the process.
    # @return this SubProcess instance
    def exec_async(cmd, *args, **opts)
      exec(false, @env, cmd, *args, **opts)
    end

    # check if this process has completed with exit code 0
    # (success) or not
    def exit_zero?
      return false unless execution_state == ExecutionState::COMPLETED

      task_info[:process_status].exitstatus.zero?
    end

    # Block caller until this subprocess has completed or aborted
    # @return the TaskInfo struct of the completed process
    def wait_on_completion
      return if @execution_thread.nil?

      @execution_thread.join
      task_info
    end

    # blocks until all processes in the given array are completed/aborted.
    #
    # the implementation polls each process after each given poll interval
    # (in ms)
    #
    # @return true if all processes exited with status 0, false in all other
    # cases
    def self.wait_on_all(running_proc, polling_interval = 100, &block)
      until running_proc.empty?
        done = get_finished(running_proc)
        running_proc -= done
        next unless block_given?

        done.each(&block) if block_given?
        sleep polling_interval / 1000
      end
    end

    # Wait for processes to complete and give a block an opportunity to
    # start one or more new processes for each completed one.
    # a given block will be handed each completed SubProcess. If the block
    # returns one or more SubProcess objects, these will be waited upon as well.
    #
    # @param running_proc      an array of running proecesses to block on
    # @param polling_interval  how often (in ms) we check the run state of the
    #                          running processes (default every 100 ms)
    # @return                  all finished processes
    #
    # Example usage:
    #
    # # start 3 processes asyncronously
    # nof_processes = 3
    # p_array = (1..nof_processes).collect do
    #   SubProcess.new(SubProcess::NONE).exec_async('ping', ['127.0.0.1'])
    # end
    #
    # # block until a process completes and then immediately start a new process
    # # until we've started 10 in total
    # p_total = SubProcess.wait_or_back_to_back(p_array) do |p|
    #   # create new processes until we reach 10
    #   unless nof_processes >= 10
    #     np = SubProcess.new.exec_async('echo', "Process #{nof_processes}")
    #     nof_processes += 1
    #   end
    #   np
    # end
    # ... here p_total will contain all 10 finished SubProcess objects
    def self.wait_or_back_to_back(running_proc, polling_interval = 100)
      all_proc = running_proc.dup
      until running_proc.empty?
        done = get_finished(running_proc)
        running_proc -= done
        next unless block_given?

        done.each do |p|
          new_proc = Array(yield(p)).select { |r| r.is_a?(SProc) }
          running_proc += new_proc
          all_proc += new_proc
        end
        sleep polling_interval / 1000
      end
      all_proc
    end

    # @return the TaskInfo representing this SubProcess, nil if
    #         process has not started
    def task_info
      @runner.task_info
    end

    # return processes that are no longer running
    def self.get_finished(running_proc)
      running_proc.select do |p|
        [ExecutionState::COMPLETED,
         ExecutionState::ABORTED,
         ExecutionState::FAILED_TO_START].include?(p.execution_state)
      end
    end

    private

    def exec(synch, env, cmd, *args, **opts)
      raise 'Subprocess already running!' unless @execution_thread.nil? || !@execution_thread.alive?

      # kick-off a fresh task runner and execution thread
      @runner = TaskRunner.new(@run_opts)
      @execution_thread = Thread.new do
        @runner.execute(env, cmd, *args, **opts)
      end
      @execution_thread.join if synch
      self
    end

    # Helper class that runs one task using the preconditions given at
    # instantiation.
    # This class is not intended for external use
    class TaskRunner
      attr_reader :task_info

      include ShellType

      # Restrict the options to Process.spawn that we support to these
      SUPPORTED_SPAWN_OPTS = %i[chdir umask unsetenv_others]

      DEFAULT_OPTS = {
        type: NONE,
        stdout_callback: nil,
        stderr_callback: nil
      }.freeze

      def initialize(opts)
        @task_info = TaskInfo.new('', nil, 0, nil, nil, String.new, String.new)
        @opts = DEFAULT_OPTS.dup.merge!(opts)
      end

      # Runs the process and blocks until it is completed or aborted.
      # The stdout and stdin streams are continuously read in parallel with
      # the process execution.
      def execute(env, cmd, *args, **opts)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          shell_out_via_popen(env, cmd, *args, **opts)
        rescue StandardError => e
          @task_info[:exception] = e
        end
        @task_info[:wall_time] = (Process.clock_gettime(
          Process::CLOCK_MONOTONIC
        ) - start_time)
      end

      private

      def valid_opts(**opts)
        return opts if opts.nil? || opts.empty?

        supported = {}
        SUPPORTED_SPAWN_OPTS.each { |o| supported[o] = opts[o] if opts.has_key?(o) }
        supported
      end

      def shell_out_via_popen(env, cmd, *args, **opts)
        opts = valid_opts(**opts)
        args = case @opts[:type]
               when NONE then get_args_native(cmd, *args, **opts)
               when BASH then get_args_bash(cmd, *args, **opts)
               else raise ArgumentError, "Unknown task type: #{@type}!!"
               end

        SProc.logger&.debug { "Start: #{task_info[:cmd_str]}" }
        SProc.logger&.debug { "Supplying env: #{env}" } unless env.nil?
        SProc.logger&.debug { "Spawn options: #{opts}" } unless opts.nil?
        Open3.popen3(env, *args) do |stdin, stdout, stderr, thread|
          @task_info[:popen_thread] = thread
          threads = do_while_process_running(stdin, stdout, stderr)
          @task_info[:process_status] = thread.value
          threads.each(&:join)
        end
      end

      def get_args_native(cmd, *args, **opts)
        cmd_args = args.flatten.map(&:to_s)
        @task_info[:cmd_str] = "#{cmd} #{cmd_args.join(' ')}"
        [cmd.to_s, *cmd_args, opts]
      end

      # convert arguments to a string prepended with bash -c
      def get_args_bash(cmd, *args, **opts)
        cmd_str = ([cmd] + args).each { |a| Shellwords.escape(a) }.join(' ')
        @task_info[:cmd_str] = "bash -c \"#{cmd_str}\""
        [@task_info[:cmd_str], opts]
      end

      def do_while_process_running(_stdin, stdout, stderr)
        th1 = process_output_stream(stdout,
                                    @task_info[:stdout], @opts[:stdout_callback])
        th2 = process_output_stream(stderr,
                                    @task_info[:stderr], @opts[:stderr_callback])
        [th1, th2]
      end

      # process an output stream within a separate thread
      def process_output_stream(stream, stream_cache = nil,
                                process_callback = nil)
        Thread.new do
          until (raw_line = stream.gets).nil?
            process_callback&.call(raw_line)
            stream_cache << raw_line unless stream_cache.nil?
          end
        rescue IOError => e
          l = SProc.logger
          l&.warn { 'Stream closed before all output were read!' }
          l&.warn { e.message }
        end
      end
    end
  end
end
