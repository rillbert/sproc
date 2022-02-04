require "minitest/autorun"
require_relative "../lib/sproc/osinfo"
require_relative "../lib/sproc/core"

module SProc
  # test the sequential process class
  class NegativeTest < Minitest::Test
    def setup
      $stdout.sync = true
      @script_path = Pathname.new(__dir__.to_s).join("data/error_gen_script.rb")
    end

    def test_ok
      s = SProc.new(
        stdout_callback: lambda { |line| assert_equal("Ok!", line.chomp) }
      ).exec_sync("ruby", [@script_path, "--success"])
      assert_equal(ExecutionState::Completed, s.execution_state)
      assert(s.exit_zero?)
    end

    def test_non_existent_cmd
      s = SProc.new.exec_async("rubbbby")
      assert_equal(ExecutionState::FailedToStart, s.execution_state)
      assert_equal(Errno::ENOENT, s.task_info.exception.class)
    end

    def test_exception_in_subprocess
      s = SProc.new.exec_sync("ruby", [@script_path, "--throw-exception"])
      assert_equal(ExecutionState::Completed, s.execution_state)
    end

    def test_exit_on_signal
      skip "Uses POSIX signals, does not work on Windows..." if OSInfo.on_windows? || OSInfo.on_mixed_env?

      s = SProc.new.exec_async("ruby", [@script_path, "--wait-on-signal"])
      assert(s.execution_state == ExecutionState::Running)

      # clobber the subprocess
      s.signal.kill
      s.wait_on_completion
      assert(s.execution_state == ExecutionState::Aborted)
    end
  end
end
