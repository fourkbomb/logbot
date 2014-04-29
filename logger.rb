require 'date'
class RBIRCBot::Logger
	def initialize sock,config
		$line_handlers["Logger"] = self.method(:log_line)
		puts "Logger loaded!"
	end
	
	def log_line sender, isOp, dest, msg, sock, bind 
		if dest.start_with? "#"
			fdate = DateTime.now.strftime "%Y-%m-%d"
			File.open "./#{dest}_#{fdate}.log", "a" do |log|
				log.puts "#{DateTime.now.strftime "[%H:%M:%S]"}<#{sender}> #{msg}"
			end
		end
	end	
end
