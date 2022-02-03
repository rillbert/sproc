require "minitest/autorun"
require_relative "../lib/sproc/osinfo"
require_relative "../lib/sproc/core"

module SProc
  # test the sequential process class
  class TestSequentialProcess < Minitest::Test
    def setup
      # avoid keeping data in stdout buffer before writing it out
      $stdout.sync = true
      # since not even a simple cmd like 'ping' has the same flags
      # under windows/linux (grrr), we need to pass different flags
      # depending on os
      @count_flag = case OSInfo.host_os
                    when OSInfo::WINDOWS then "-n"
                    when OSInfo::LINUX then "-c"
                    else raise "Unsupported OS!"
      end
      @script_path = Pathname.new("#{__dir__}").join("data/testscript.rb")
    end

    def test_exception
      s = SProc.new.exec_sync("ruby",[@script_path, "hej", "hopp"])
      # p s.task_info.inspect
      # puts "stdout: #{s.task_info.stdout}"
      # puts "exit code: #{s.task_info.process_status.exitstatus}"
      assert_equal(ExecutionState::COMPLETED,s.execution_state)
    end
  end
end