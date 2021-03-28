require_relative 'core'

# This module is written to provide sub-process
# execution with some human readable logging of process start/stop/errors
#
# It wraps SProc instances and execution with calls to logging methods
# that tries to make the resulting log user friendly
module SProc
  module Reporting
    class << self
      attr_accessor :logger
    end

    def logger
      Reporting.logger
    end

    # Run a process synchronuously via the native shell and log
    # output suitable for a build log
    #
    # @param cmd_name   a String containing a descriptive
    #                        name for what the process will do.
    # @param cmd, args, opts see SProc.exec_sync
    #
    # @return                the SProc instance containing the completed process
    def report_sync(cmd_name, cmd, *args, **opts)
      p = create_proc_and_log(cmd_name,
                              ShellType::NONE, :exec_sync,
                              cmd, args, opts)
      report_completed(p)
      p
    end

    # Run a process asynchronuously via the native shell and log
    # output suitable for a build log
    #
    # @param cmd_name   a String containing a descriptive
    #                        name for what the process will do.
    # @param cmd, args, opts see SProc.exec_sync
    #
    # @return                the created SProc instance
    def report_async(cmd_name, cmd, *args, **opts)
      create_proc_and_log(cmd_name,
                          ShellType::NONE, :exec_async,
                          cmd, args, opts)
    end

    # Run a process asynchronuously via the Bash shell and log
    # output suitable for a build log
    #
    # @param cmd_name   a String containing a descriptive
    #                        name for what the process will do.
    # @param cmd, args, opts see SProc.exec_sync
    #
    # @return                the created SProc instance
    def report_async_within_bash(cmd_name, cmd, *args, **opts)
      create_proc_and_log(cmd_name,
                          ShellType::BASH, :exec_async,
                          cmd, args, opts)
    end

    # Log output from a completed/aborted process
    #
    # @param process   the SProc instance that has run
    # @return          true/false corresponding to process success
    def report_completed(process)
      friendly_name = if @log_friendly_name_map&.key?(process)
                  "#{@log_friendly_name_map[process]}"
                else
                  process.task_info[:cmd_str][0,10] + "..."
                end
      started_ok = true
      case process.execution_state
      when ExecutionState::COMPLETED
        process.exit_zero? && log_completed_ok(friendly_name, process.task_info)
        !process.exit_zero? && log_completed_err(friendly_name, process.task_info)
      when ExecutionState::ABORTED
        log_aborted(friendly_name, process.task_info)
        started_ok = false
      when ExecutionState::FAILED_TO_START
        log_failed_start(friendly_name, process.task_info)
        started_ok = false
      else
        log_unexpected(friendly_name, process.task_info)
      end
      started_ok && process.exit_zero?
    end

    private

    def create_proc_and_log(cmd_name, type, method, cmd, args, opts)
      log_start(cmd_name, type, method, cmd, args, **opts)
      p = SProc.new(type: type).send(method, cmd, args, **opts)
      @log_friendly_name_map ||= {}
      @log_friendly_name_map[p] = cmd_name
      p
    end

    def log_method_result_ok(friendly_name, delta)
      logger.info do
        "#{friendly_name} completed successfully after #{delta.round(3)}s"
      end
    end

    def log_method_result_error(friendly_name_method, delta, exc)
      logger.error do
        "#{friendly_name_method} aborted by #{exc.class} after #{delta.round(3)}s\n"\
        "Exception info: #{exc.message}"
      end

      logger.debug do
        exc.backtrace.to_s
      end
    end

    def log_start(cmd_name, type, method, cmd, *args, **opts)
      logger.info do
        async_str = method == :exec_async ? 'asynchronuously' : 'synchronuously'
        type_str = type == ShellType::NONE ? 'without shell' : 'within the bash shell'
        "'#{cmd_name}' executing #{async_str} #{type_str}..."
      end
      logger.debug do
        msg = String.new("Starting #{cmd}")
        msg << " with args: #{args.flatten.inspect}" unless args.nil? || args.empty?
        msg << " and opts: #{opts.inspect}" unless opts.nil? || opts.empty?
        msg
      end
    end

    def log_one_dll(regex, cmd_str, time)
      m = regex.match(cmd_str)
      s = m.nil? ? cmd_str : m[1]
      max = 45
      s = s.length > max ? s.slice(0..max - 1) : s.ljust(max)
      logger.info { "#{s} took #{time.round(3)}s." }
    end

    def log_aborted(friendly_name, p_info)
      logger.error do
        "'#{friendly_name}' aborted!\n"\
        "When running: #{p_info[:cmd_str]}\n"\
        "#{merge_proc_output(p_info)}"\
        "#{p_info[:process_status] unless p_info[:process_status].nil?}"
      end
    end

    def log_failed_start(friendly_name, p_info)
      logger.error do
        "'#{friendly_name}' not run!\n"\
        "Could not start process using: #{p_info[:cmd_str]}\n"\
        "#{merge_proc_output(p_info)}"
      end
    end

    def log_completed_ok(friendly_name, p_info)
      logger.info do
        "'#{friendly_name}' completed successfully after #{p_info[:wall_time].round(3)}s"
      end
      logger.debug do
        "Cmd: #{p_info[:cmd_str]}"
      end
    end

    def log_completed_err(friendly_name, p_info)
      logger.error do
        "'#{friendly_name}' completed with exit code "\
        "#{p_info[:process_status].exitstatus}\n"\
        "When running: #{p_info[:cmd_str]}\n"\
        "after #{p_info[:wall_time].round(3)}s\n"\
        "#{merge_proc_output(p_info)}"
      end
    end

    def log_unexpected(friendly_name, p_info)
      logger.error do
        "'#{friendly_name}' caused unexpected error!"\
        ' Trying to display info on a running process'\
        "(#{p_info[:cmd_str]})"
      end
    end

    # @return String with sections for each non-empty output stream
    #                and exception messages
    def merge_proc_output(p_info)
      inf_str = %i[stdout stderr].collect do |sym|
        next('') if p_info[sym].empty?

        "--- #{sym} ---\n#{p_info[sym]}"
      end.join("\n")

      exc = p_info[:exception]
      inf_str << "--- exception ---\n#{exc}\n" unless exc.nil?
      inf_str
    end
  end
end
