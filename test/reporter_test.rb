require 'minitest/autorun'
require_relative '../lib/sproc/utils'
require_relative '../lib/sproc/reporting'

module SProc
  # test the sequential process class
  class ReporterTests < Minitest::Test

    # bring in the reporting methods
    include Reporting

    def setup
      # avoid keeping data in stdout buffer before writing it out
      $stdout.sync = true
      # since not even a simple cmd like 'ping' has the same flags
      # under windows/linux (grrr), we need to pass different flags
      # depending on os
      @count_flag = case OSInfo.host_os
                    when OSInfo::OS::WINDOWS then '-n'
                    when OSInfo::OS::LINUX then '-c'
                    else raise 'Unsupported OS!'
                    end
      @logger_io = StringIO.new
      Reporting.logger = Logger.new(@logger_io)
      Reporting.logger.level = Logger::INFO
    end

    # Kick-off single, synchronous processes and wait for
    # their completion
    def test_report_sync
      sp = report_sync('Pinging Localhost', 'ping', [@count_flag, '2', '127.0.0.1'])

      # we expect this to succeed (ie exit with '0')
      assert_equal(true, sp.exit_zero?)
      assert(!@logger_io.string.empty?)
    end

    def test_report_async
      sp = report_async('Pinging Localhost', 'ping', [@count_flag, '2', '127.0.0.1'])
      sp.wait_on_completion
      report_completed(sp)

      # we expect this to succeed (ie exit with '0')
      assert_equal(true, sp.exit_zero?)
      # assert_equal("hej",@logger_io.string)
      assert(!@logger_io.string.empty?)
    end
  end
end
