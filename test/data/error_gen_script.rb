require "open3"

# begin
# stdin, stdout, stderr, wait_thread = Open3.popen3({}, "ruby", "hej")
# rescue => e
#   puts e.inspect
# end
# exit 1

if $PROGRAM_NAME == $0
  exit 0 if ARGV.empty?

  if ARGV.length == 1
    case ARGV[0]
    when "--success"
      puts "Ok!"
      exit 0
    when "--throw-exception"
      raise "Throwing exception"
    when "--wait-on-signal"
      puts "sleeping"
      sleep 3
    end
  end
end
