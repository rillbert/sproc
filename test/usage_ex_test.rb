require "minitest/autorun"
require "logger"
require "stringio"
require "etc"
require_relative "../lib/sproc/osinfo"
require_relative "../lib/sproc/core"

module SProc
  # test the sequential process class
  class UsageExampleTests < Minitest::Test
    def setup
      # avoid keeping data in stdout buffer before writing it out
      $stdout.sync = true
      # since not even a simple cmd like 'ping' has the same flags
      # under windows/linux (grrr), we need to pass different flags
      # depending on os
      @count_flag = case OSInfo.host_os
                    when OSInfo::OS::WINDOWS then "-n"
                    when OSInfo::OS::LINUX then "-c"
                    else raise "Unsupported OS!"
      end
    end

    # Kick-off single, synchronous processes and wait for
    # their completion
    def test_single_sync
      # Intantiate a 'container' for a sub-process that will invoke
      # the subprocess under the default shell for the platform
      sp = SProc.new(type: SProc::NONE)

      # Run 'ping -c 2 127.0.0.1' synchronously as a subprocess, that is,
      # we block until it has completed.
      sp.exec_sync("ping", [@count_flag, "2", "127.0.0.1"])

      # we expect this to succeed (ie exit with '0')
      assert_equal(true, sp.exit_zero?)
      assert_equal(ExecutionState::COMPLETED, sp.execution_state)

      # we can access more info about the completed process via
      # its associated TaskInfo struct:
      ti = sp.task_info
      assert_equal("ping #{@count_flag} 2 127.0.0.1", ti.cmd_str)

      # ping should take at least 1 sec to complete
      assert(ti.wall_time > 0.5)

      # we can access the underlying ruby 'ProcessStatus' object if
      # we really need to
      assert_equal(false, ti.process_status.nil?)
      assert_equal(0, ti.process_status.exitstatus)
      assert_equal(false, ti.popen_thread.alive?)
      assert_equal(true, ti.exception.nil?)

      # the output from the command is captured in stdout.
      # stderr should be empty for successful commands
      assert_equal(false, ti.stdout.empty?)
      assert_equal(true, ti.stderr.empty?)

      # expect this to complete with exit code != 0 since host does not
      # exist
      sp.exec_sync("ping", [@count_flag, "2", "fake_host"])
      assert_equal(ExecutionState::COMPLETED, sp.execution_state)
      assert_equal(false, sp.exit_zero?)
      assert_equal(true, sp.task_info.exception.nil?)

      # expect this to never start a process since the cmd not exists
      sp.exec_sync("pinggg", [@count_flag, "1", "fake_host"])
      assert_equal(ExecutionState::FAILED_TO_START, sp.execution_state)
      assert_equal(false, sp.exit_zero?)
      # A call to non-existing command will return ERRNO::ENOENT
      assert_equal(false, sp.task_info.exception.nil?)
      assert_instance_of(Errno::ENOENT, sp.task_info.exception)
      # no cmd run so no stderr info
      assert_equal(true, sp.task_info.stderr.empty?)
    end

    def test_single_async
      # Intantiate a 'container' for a sub-process that will invoke
      # the subprocess under the default shell for the platform
      sp = SProc.new(type: SProc::NONE)

      # Run 'ping -c 2 127.0.0.1' asynchronously as a subprocess, that is,
      # we don't block while it is running.
      sp.exec_async("ping", [@count_flag, "2", "127.0.0.1"])

      # ping should take at least 1 sec to complete so we
      # expect the subprocess to run when these asserts are executed
      assert_equal(ExecutionState::RUNNING, sp.execution_state)
      assert_equal(false, sp.exit_zero?)
      ti = sp.task_info
      # the wall time is not filled in until completion
      assert_equal(0, ti.wall_time)
      # we can access the underlying ruby 'ProcessStatus' object if
      # we really need to
      assert_equal(true, ti.process_status.nil?)
      # we don't know if the popen_thread has been created here yet
      assert_equal(true, ti.popen_thread.alive?) unless ti.popen_thread.nil?

      # Wait for the sub-process to complete
      sp.wait_on_completion
      # Now we expect the same as during a corresponding synchronous
      # invokation
      assert_equal(ExecutionState::COMPLETED, sp.execution_state)
      assert_equal(true, sp.exit_zero?)
      ti = sp.task_info
      assert_equal("ping #{@count_flag} 2 127.0.0.1", ti.cmd_str)
      # ping should take at least 1 sec to complete
      assert(ti.wall_time > 0.5)
      assert_equal(false, ti.stdout.empty?)
      assert_equal(true, ti.stderr.empty?)
      assert_equal(true, ti.exception.nil?)
    end

    def test_logging
      # 'Switch on' logging for SProc by setting the class member
      # to a logger object
      logger_io = StringIO.new
      SProc.logger = Logger.new(logger_io)
      # set logging to 'debug'
      SProc.logger.level = Logger::DEBUG

      # Intantiate a 'container' for a sub-process that will invoke
      # the subprocess under the default shell for the platform
      sp = SProc.new(type: SProc::NONE)

      # Run 'ping -c 2 127.0.0.1' asynchronously as a subprocess, that is,
      # we don't block while it is running.
      sp.exec_sync("ping", [@count_flag, "2", "127.0.0.1"], chdir: "..")
      assert(sp.exit_zero?)

      # check that something has been logged...
      assert(!logger_io.string.empty?)

      # 'Switch off' logging for all coming SProc operations
      SProc.logger = nil
    end

    def test_wait_on_all
      # Kick-off two async subprocesses
      sp1 = SProc.new(type: SProc::NONE).exec_async("ping", [@count_flag, "2", "127.0.0.1"])
      sp2 = SProc.new(type: SProc::NONE).exec_async("ping", [@count_flag, "1", "127.0.0.1"])
      # block until both processes are complete using default poll loop interval
      SProc.wait_on_all([sp1, sp2])
      # check that they are complete
      assert(sp1.exit_zero?)
      assert(sp2.exit_zero?)

      # kick-off two new async processes
      sp1.exec_async("ping", [@count_flag, "2", "127.0.0.1"])
      sp2.exec_async("ping", [@count_flag, "1", "127.0.0.1"])
      # wait until both processes are complete but exec the supplied
      # block as soon as a process is complete.
      count = 0
      SProc.wait_on_all([sp1, sp2], 50) do |completed|
        # we expect the SProc instance to be completed
        assert(completed.exit_zero?)
        count += 1
      end
      # both processes are complete before we reach this code
      assert(2, count)
    end

    def test_wait_or_back_to_back
      # The total number of subprocesses we will kick-off in this test
      total_nof_processes = 15

      # Kick-off one process to start with
      p_array = [
        SProc.new(type: SProc::NONE).exec_async("ping", [@count_flag, "2", "127.0.0.1"])
      ]

      nof_not_stared_yet = total_nof_processes - 1
      completed = 0
      # For each completed process, kick-of one or more until we've
      # reached 'nof_not_stared_yet'
      p_total = SProc.wait_or_back_to_back(p_array) do |p|
        p_new = []
        # create and start a random number of processes. Not more than we have
        # CPU cores or that have not yet been started
        nof_pings = rand(1..3)
        [
          Etc.nprocessors, nof_not_stared_yet
        ].min.times do
          p_new << SProc.new(type: SProc::NONE).exec_async("ping", [@count_flag, nof_pings, "127.0.0.1"])
          nof_not_stared_yet -= 1
        end

        # check that the given process has completed
        assert(p.exit_zero?)
        completed += 1

        # return the newly started processes
        p_new
      end

      assert_equal(total_nof_processes, completed)
      assert_equal(total_nof_processes, p_total.length)
    end
  end
end
