require "shellwords"
require "open3"

module SProc
  # Defines the supported shell environments in which a subprocess
  # can be run.
  module ShellType
    SHELL_TYPES = [
      # Start the process without any shell
      NONE = 0,
      # Indicates that the subprocess shall run within a created
      # 'bash' instance.
      BASH = 1
    ].freeze
  end

  # The available execution states of a the subprocess
  # running within an SProc instance.
  module ExecutionState
    # The process is initiated but does not yet run
    NOT_STARTED = 0
    # The process is running
    RUNNING = 1
    # The process has previously been running but is now aborted
    ABORTED = 2
    # The process has previously been running but has now run to completion
    COMPLETED = 3
    # The process failed to start and thus, have never been running
    FAILED_TO_START = 4
  end

  # Execute a command in a subprocess, either synchronuously or asyncronously.
  class SProc
    # A struct that represents queryable info about the task run by this SProc
    #
    # cmd_str:: the invokation string used to start the process
    # exception:: the exception terminating the process (nil if everything ok)
    # wall_time:: the time (in s) between start and completion of the process
    # process_status:: the ProcessStatus object (see Ruby docs)
    # popen_thread:: the thread created by the popen call, nil before started
    # stdout:: a String containing all output from the process' stdout
    # stderr:: a String containing all output from the process' stderr
    TaskInfo = Struct.new(
      :cmd_str, # the invokation string used to start the process
      :exception, # the exception terminating the process (nil if everything ok)
      :wall_time, # the time (in s) between start and completion of the process
      :process_status, # the ProcessStatus object (see Ruby docs)
      :popen_thread, # the thread created by the popen call, nil before started
      :stdout, # a String containing all output from the process' stdout
      :stderr # a String containing all output from the process' stderr
    )

    @logger = nil
    class << self
      # a class-wise logger instance
      attr_accessor :logger
    end

    def logger
      self.class.logger
    end

    include ShellType
    include ExecutionState

    # prepare to run a sub process
    # type::            the ShellType used to run the process within
    # stdout_callback:: a callback that will receive all stdout output
    #                   from the process as it is running (default nil)
    # stderr_callback:: a callback that will receive all stderr output
    #                   from the process as it is running (default nil)
    #
    # env::             a hash containing key/value pairs of strings that\
    #                   set the environment variable 'key' to 'value'. If value
    #                   is nil, that env variable is unset
    #
    # == Example callback signature
    #
    # def my_stdout_cb(line)
    def initialize(type: ShellType::NONE, stdout_callback: nil,
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

    # Start the sub-process and block until it has completed.
    #
    # cmd::    the command to execute within the subprocess
    # args::   an array with all arguments to the command
    # opts::   a hash with options that influence the spawned process.
    #          The supported options are: chdir, umask and unsetenv_others
    #          See Process.spawn for definitions
    #
    # return:: this SProc instance
    def exec_sync(cmd, *args, **opts)
      exec(true, @env, cmd, *args, **opts)
    end

    # Start the process non-blocking. Use one of the wait... methods
    # to later block on the process.
    #
    # cmd::    the command to execute within the subprocess
    # args::   an array with all arguments to the command
    # opts::   a hash with options that influence the spawned process.
    #          The supported options are: chdir, umask and unsetenv_others
    #          See Process.spawn for definitions
    #
    # return:: this SProc instance
    def exec_async(cmd, *args, **opts)
      exec(false, @env, cmd, *args, **opts)
    end

    # return:: +true+ if this process has completed with exit code 0
    #          (success). +false+ otherwise
    def exit_zero?
      return false unless execution_state == ExecutionState::COMPLETED

      task_info[:process_status].exitstatus.zero?
    end

    # Block the caller as long as this subprocess is running.
    # If this SProc has not been started, the call returns
    # immediately
    #
    # return:: the TaskInfo struct of the completed process or
    #          nil if the subprocess has not yet been started.
    def wait_on_completion
      return nil if @execution_thread.nil?

      @execution_thread.join
      task_info
    end

    # Return the execution state of this SProc. Note that it is not
    # identical with the life-cycle of the underlying ProcessStatus object
    #
    # return:: current ExecutionState
    def execution_state
      return ExecutionState::NOT_STARTED if @execution_thread.nil?

      # Count this SProc as running as long as the thread
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

    # return:: the TaskInfo representing this SProc, nil if
    # process has not started
    def task_info
      @runner.task_info
    end

    # Blocks until all processes in the given array are completed/aborted.
    #
    # If the caller submits a block, that block is called once for each
    # completed SProc as soon as possible after the SProc has completed.
    #
    # Polling is used to implement this method so there is a jitter from the
    # point in time when an SProc has completed until its state is polled.
    # The caller can give the polling interval in ms as a parameter.
    #
    # running_proc:: an array of SProc objects to wait on
    # polling_interval:: how often shall the SProc array be checked, in ms.
    #                    Default is 100ms
    # return:: true if all processes exited with status 0, false in all other
    # cases
    #
    # === Example with block
    #
    # Wait for two SProc with a polling interval of 50ms
    #  SProc.wait_on_all([sp1, sp2], 50) do |completed|
    #    # do stuff with the completed SProc...
    #    assert(completed.exit_zero?)
    #  end
    def self.wait_on_all(running_proc, polling_interval = 100, &block)
      until running_proc.empty?
        done = get_finished(running_proc)
        running_proc -= done
        next unless block

        done.each(&block) if block
        sleep polling_interval / 1000
      end
    end

    # Wait for subprocesses to complete and give a block an opportunity to
    # start one or more new processes for each completed one.
    # a given block will be handed each completed SProc. If the block
    # returns one or more SProc objects, these will be waited upon as well.
    #
    # running_proc::      an array of running proecesses to wait on
    # polling_interval::  how often (in ms) the run state of the
    #                     running processes is checked (default every 100 ms)
    # return::            all finished processes
    #
    # === Example usage:
    #
    #  # start three subprocesses
    #  nof_processes = 3
    #  p_array = (1..nof_processes).collect do
    #    SProc.new(SProc::NONE).exec_async('ping', ['127.0.0.1'])
    #  end
    #
    #  # block until a process completes and then immediately start a new process
    #  # until we've started 10 in total
    #  p_total = SProc.wait_or_back_to_back(p_array) do |p|
    #    # create new processes until we reach 10
    #    unless nof_processes >= 10
    #      np = SProc.new.exec_async('echo', "Process #{nof_processes}")
    #      nof_processes += 1
    #    end
    #    # the new subprocess is returned from the block and thus included
    #    # in the pool of subprocess to wait for
    #    np
    #  end
    #
    # from here p_total will contain all 10 finished SProc objects
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

    # Returns the processes in the given array that at a previous
    # point in time was ordered to start but are not currently running.
    #
    # sproc_array:: an array of SProc objects
    #
    # return:: an array of SProc objects not running (but previously started)
    def self.get_finished(sproc_array)
      sproc_array.select do |p|
        [ExecutionState::COMPLETED,
          ExecutionState::ABORTED,
          ExecutionState::FAILED_TO_START].include?(p.execution_state)
      end
    end

    private

    # a helper method that supports both synch/async execution
    # depending on the supplied args
    def exec(synch, env, cmd, *args, **opts)
      raise "Subprocess already running!" unless @execution_thread.nil? || !@execution_thread.alive?

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
        @task_info = TaskInfo.new("", nil, 0, nil, nil, "", "")
        @opts = DEFAULT_OPTS.dup.merge!(opts)
      end

      # Runs the process and blocks until it is completed or aborted.
      # The stdout and stdin streams are continuously read in parallel with
      # the process execution.
      def execute(env, cmd, *args, **opts)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          shell_out_via_popen(env, cmd, *args, **opts)
        rescue => e
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
        @task_info[:cmd_str] = "#{cmd} #{cmd_args.join(" ")}"
        [cmd.to_s, *cmd_args, opts]
      end

      # convert arguments to a string prepended with bash -c
      def get_args_bash(cmd, *args, **opts)
        cmd_str = ([cmd] + args).each { |a| Shellwords.escape(a) }.join(" ")
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
            # log stream output directly in debug mode
            SProc.logger&.debug { raw_line }
            stream_cache << raw_line unless stream_cache.nil?
          end
        rescue IOError => e
          l = SProc.logger
          l&.warn { "Stream closed before all output were read!" }
          l&.warn { e.message }
        end
      end
    end
  end
end
