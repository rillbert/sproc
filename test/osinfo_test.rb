require "minitest/autorun"
require "logger"
require_relative "../lib/sproc/osinfo"

module SProc
  # test the sequential process class
  class TestOSInfo < Minitest::Test
    def setup
      # need to cheat and get the OS the same way the module does
      # to be able to test...
      @os_from_config = OSInfo.send(:exec_env)
    end

    def test_os_info
      case @os_from_config
      when OSInfo::BSD then assert(OSInfo.on_bsd?)
      when OSInfo::CYGWIN then assert(OSInfo.on_cygwin?)
      when OSInfo::LINUX then assert(OSInfo.on_linux?)
      when OSInfo::MINGW then assert(OSInfo.on_mingw?)
      when OSInfo::OSX then assert(OSInfo.on_osx?)
      when OSInfo::WINDOWS then assert(OSInfo.on_windows?)
      else
        fail("Unsupported OS: #{@os_from_config}")
      end

      case @os_from_config
      when OSInfo::CYGWIN, OSInfo::MINGW
        assert(OSInfo.on_mixed_env?)
        assert(!OSInfo.on_windows?)
        assert_equal(OSInfo::WINDOWS, OSInfo.host_os)
      end
    end
  end
end
