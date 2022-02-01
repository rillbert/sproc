require "rbconfig"

# helper methods to find out os and execution environment
module SProc
  module OSInfo
    # the supported exec environments
    module OS
      WINDOWS = 0
      LINUX = 1
      MINGW = 2
      CYGWIN = 3
      OSX = 4
      BSD = 5
      UNKNOWN = 100
    end

    # returns the current execution environment
    def self.os_context
      case RbConfig::CONFIG["host_os"]
      when /mswin/ then OS::WINDOWS
      when /mingw/ then OS::MINGW
      when /cygwin/ then OS::CYGWIN
      when /darwin/ then OS::OSX
      when /linux/ then OS::LINUX
      when /bsd/ then OS::BSD
      else OS::UNKNOWN
      end
    end

    # return the current underlying operating system
    def self.host_os
      if [OS::WINDOWS, OS::MINGW, OS::CYGWIN].include?(os_context)
        OS::WINDOWS
      else
        os_context
      end
    end

    def on_windows?
      OSInfo.host_os == OS::WINDOWS
    end

    def on_linux?
      OSInfo.os_context == OS::LINUX
    end

    def on_bsd?
      OSInfo.os_context == OS::BSD
    end

    def on_osx?
      OSInfo.os_context == OS::OSX
    end
  end
end
