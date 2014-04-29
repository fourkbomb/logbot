class RBIRCBot::Base
	def initialize s,c
		$rcCmds["quit"] = self.method(:quit)
		$rcCmds["join"] = self.method(:join)
		$rcCmds["part"] = self.method(:leave)
	end
	def quit(sender,dest,args,sock,bind)
		if not args.empty?
			sock.puts "QUIT :"+args
		else
			sock.puts "QUIT :OOM Killed"
		end
	end
	
	def join(sender,dest,args,sock,bind)
		if not args.empty?
			sock.puts "JOIN :"+args
		end
	end
	
	def leave(sender,dest,args,sock,bind)
		if not args.empty?
			sock.puts "PART :"+args
		end
	end
end
