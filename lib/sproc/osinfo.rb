require "rbconfig"

module SProc
  # helper methods to find out os and execution en
  module OSInfo
    def self.on_windows?
      exec_env == WINDOWS
    end

    def self.on_mixed_env?
      [MINGW, CYGWIN].include?(exec_env)
    end

    def self.on_linux?
      exec_env == LINUX
    end

    def self.on_osx?
      exec_env == OSX
    end

    def self.on_bsd?
      exec_env == BSD
    end

    def self.on_mingw?
      exec_env == MINGW
    end

    def self.on_cygwin?
      exec_env == CYGWIN
    end

    def self.host_os
      return WINDOWS if [MINGW, CYGWIN].include?(exec_env)

      exec_env
    end

    WINDOWS = :windows
    LINUX = :linux
    OSX = :osx
    BSD = :bsd
    UNKNOWN = :unknown
    MINGW = :mingw
    CYGWIN = :cygwin

    # determine the execution environment, intended for internal
    # use only
    def self.exec_env
      case RbConfig::CONFIG["host_os"]
      when /mswin/ then WINDOWS
      when /mingw/ then MINGW
      when /cygwin/ then CYGWIN
      when /darwin/ then OSX
      when /linux/ then LINUX
      when /bsd/ then BSD
      else UNKNOWN
      end
    end
    private_class_method :exec_env

    # the supported exec environments
    # module OS
    #   WINDOWS = 0
    #   LINUX = 1
    #   MINGW = 2
    #   CYGWIN = 3
    #   OSX = 4
    #   BSD = 5
    #   UNKNOWN = 100
    # end

    # # returns the current execution environment
    # def self.os_context
    #   case RbConfig::CONFIG["host_os"]
    #   when /mswin/ then OS::WINDOWS
    #   when /mingw/ then OS::MINGW
    #   when /cygwin/ then OS::CYGWIN
    #   when /darwin/ then OS::OSX
    #   when /linux/ then OS::LINUX
    #   when /bsd/ then OS::BSD
    #   else OS::UNKNOWN
    #   end
    # end
    # private_class_method :os_context

    # # return the current underlying operating system
    # def self.host_os
    #   if [OS::WINDOWS, OS::MINGW, OS::CYGWIN].include?(os_context)
    #     OS::WINDOWS
    #   else
    #     os_context
    #   end
    # end

    # def on_windows?
    #   OSInfo.host_os == OS::WINDOWS
    # end

    # def on_linux?
    #   OSInfo.os_context == OS::LINUX
    # end

    # def on_bsd?
    #   OSInfo.os_context == OS::BSD
    # end

    # def on_osx?
    #   OSInfo.os_context == OS::OSX
    # end
  end
end
