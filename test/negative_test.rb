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

    def test_exception
      s = SProc.new.exec_sync("ruby", [@script_path, "--throw-exception"])
      assert_equal(ExecutionState::Completed, s.execution_state)
    end

    def test_exit_on_signal
      s = SProc.new.exec_async("ruby", [@script_path, "--wait-on-signal"])
      assert(s.execution_state == ExecutionState::Running)

      # clobber the subprocess
      s.signal.kill
      s.wait_on_completion
      assert(s.execution_state == ExecutionState::Aborted)
    end
  end
end
