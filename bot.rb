#!/usr/bin/env ruby
require 'socket'
require 'openssl'
require 'date'
Process::Sys.setuid 1000
$ops = ["forkbomb!~forkbomb@unaffiliated/forkbomb"]
$modules = {}
$line_handlers = {}

class RBIRCBot
end

def load_module(name)
	path = "./#{name.downcase}.rb"
	$".delete Dir.pwd+"/#{name.downcase}.rb"
	res = "Loaded."
	begin
		$modules.delete name
		require path
		r = eval "$modules['#{name}'] = RBIRCBot::#{name}.new $s, $config"
		if r.is_a? Exception
			raise r
		end
	rescue Exception => err
		res = "Failed to load: " + err.to_s
		puts "Failed to load module #{name}: #{err.to_s}"
		puts "Stack trace:"
		puts "  " + err.backtrace.join("\n  ")
	end
	return res
end

$config = {
	'nick'		=> 'rubybomb',
	'ident'		=> 'rubybomb',
	'realname'	=> 'loop { fork { bomb } }',
	'sasluser'	=> 'PaperBag',
	'saslpass'	=>  File.open "./password" do |g| g.gets.strip end 
	'channels'	=> '##hypnotoad',
	'host'		=> 'chat.au.freenode.net',
	'port'		=> '+6697',
	'modules'	=> "Base,Logger"

}
ssl = false
pnum = 6667
if $config['port'].is_a? String
	temp = $config['port'].to_i
	if temp < 1
		temp = 6667
		puts "!! Failed to parse port. Assuming 6667"
	else
		ssl = $config['port'][0]  == "+"
		puts "SSL: " + ssl.to_s
	end
	pnum = temp
end

#### Socket initialisation
	
$s = TCPSocket.new $config['host'], pnum

if ssl
	$s = OpenSSL::SSL::SSLSocket.new $s
	$s.connect
end

#### Handling the initial connection

if not $config['saslpass'].empty? and not $config['sasluser'].empty?
	$s.puts 'CAP REQ sasl'
end
$s.puts 'NICK ' + $config['nick']
$s.puts 'USER ' + $config['ident'] + ' 8 * :' + $config['realname']

while line = $s.gets
	line.chomp!
	puts line
	if line =~ /^PING (:.*)/
		$s.puts "PONG #{$1}"
		next
	elsif line == "AUTHENTICATE +"
		require "base64"
		res = "AUTHENTICATE " + Base64.encode64($config['sasluser'] + "\0" + $config['sasluser'] + "\0" + $config['saslpass'])
		$s.puts res
		next
	elsif line =~ /^:\S+ CAP \S+ ACK :sasl/
		$s.puts "AUTHENTICATE PLAIN"
		next
	elsif line =~ /^:\S+ 90([345]) ./
		$s.puts "CAP END"
		if $1 != "3"
			$s.puts "QUIT"
			puts "Something went wrong with SASL!"
			exit 1
		end
		break
	elsif line =~ /^:\S+ 433 ./
		$config['nick'] += "_"
		puts "NICK #{$config['nick']}"
	elsif line =~ /^:\S+ 003 ./
		if $config['channels']
			$s.puts "JOIN :" + $config['channels'].split(',').map{|x| chan[0]=="#"? "#"+chan : chan }
			$config['channels'] = nil
		end
		break
	end
end
if $config['channels']
	chans = []
	$config['channels'].split(',').map{|chan| chans.push chan[0]=="#"? chan.to_s : "#"+chan.to_s }
	puts "join: " + chans.to_s
	$s.puts "JOIN :" + chans.join(",")
	$config['channels'] = nil
end


#### built-in commands

def cmd_rc_eval(sender,dest,args,sock,bind)
	result = "no result"
	begin
		result = (eval args).to_s
		if result.empty?
			result = "no result"
		end
	rescue Exception => err
		result = "Exception: " + err.to_s
		puts err.to_s
	end
	sock.puts "PRIVMSG "+dest+" :"+result
end

def cmd_rc(sender,isOp,dest,args,sock,bind)
	return if not isOp
	d = args.split
	cmd = d.shift.downcase
	args = d.join " "
	if $rcCmds.has_key? cmd 
		$rcCmds[cmd].call(sender,dest,args,sock,bind)
	else
		sock.puts "NOTICE #{sender} :No such RC command - valid ones: #{$rcCmds.keys.join ", "}"
	end
end

def cmd_rc_load(sender,dest,args,sock,bind)
	toLoad = args.split " "
	sock.puts "PRIVMSG #{dest} :#{sender}: #{load_module toLoad[0].capitalize}"
end	

$rcCmds = {"eval" => self.method(:cmd_rc_eval), "load" => self.method(:cmd_rc_load)}

$cmds = {"rc" => self.method(:cmd_rc)}

#### handle messages from the socket

def handle_line(line,sock)
	line.chomp!
	line.sub! /^:/, ""
	pre,msg = line.split ":", 2
	info = pre.split " "

	hostmask = info.shift
	what = info.shift.upcase
	return if what == "372" or what == "375"
	if what == "376"
		for i in $config['modules'].split ","
			load_module i
		end
	end
	dest = info.shift
	op = $ops.include? hostmask
	nick,mask = hostmask.split "!"
	dest = nick if dest == $config["nick"]
	if hostmask =~ /^PING/
		sock.puts "PONG :#{msg}"
		return
	end
	should_reply = (what != "NOTICE")
	if msg =~ /^\x01PING (.+?)\x01/ and should_reply
		sock.puts "NOTICE #{nick} :\x01PING #{$1}\x01"
	elsif msg =~ /^\x01TIME\x01/ and should_reply
		sock.puts "NOTICE #{nick} :\x01TIME #{DateTime.now.strftime("%a %b %d %H:%M:%S %Y %Z")}\x01"
	elsif msg =~ /^\x01SOURCE\x01/ and should_reply
		sock.puts "NOTICE #{nick} :\x01SOURCE [unavailable]\x01"
	elsif msg =~ /^\x01DALEK\x01/ and should_reply
		sock.puts "NOTICE #{nick} :\x01EXTERMINATE\x01"
	elsif msg =~ /^\x01VERSION\x01/ and should_reply
		sock.puts "NOTICE #{nick} :\x01VERSION rubybomb v0.1 - a modularised, threaded IRC bot written in Ruby\x01"
	elsif msg =~ /^\x01CLIENTINFO\x01/ and should_reply
		sock.puts "NOTICE #{nick} :\x01CLIENTINFO VERSION PING TIME SOURCE\x01"
	end
	if msg =~ /^\+/ and what == "PRIVMSG"
		msg.sub! /^\+(.+?) /, ""
		if $cmds.has_key? $1
			begin
				$cmds[$1].call(nick,op,dest,msg,sock,binding)
			rescue Exception => err
				puts "!!!! FATAL EXCEPTION WHILE RUNNING #{$1} (#{$cmds[$1]}) !!!!"
				puts "Exception: " + err.to_s
				puts "Stack trace:"
				puts err.backtrace.join "\n"
				sock.puts "PRIVMSG #{dest} :An error occurred. Consult STDOUT for details."
			end
		end
	elsif what == "PRIVMSG"
		for i in $line_handlers.values
			begin
				i.call(nick,op,dest,msg,sock,binding)
			rescue Exception => err
				puts "!!!! FATAL EXCEPTION WHILE RUNNING LINE HANDLER #{$1} !!!!"
				puts "Exception: " + err.to_s
				puts "Stack trace:"
				puts err.backtrace.join "\n"
				sock.puts "NOTICE #{nick} :An error occurred. Consult STDOUT or consult an admin for details."
			end
		end
	end 
	if what =~ /PRIVMSG/i or what =~ /NOTICE/i
		puts "[#{dest}]<#{nick}> #{msg}"
	end
end


#### threads
$threads = [];
$queue = Queue.new
$GIVE_UP = false
10.times {
	$threads.push (Thread.new($s) { |socket|
		while not $GIVE_UP
			elm = $queue.pop
			handle_line(elm, socket)
		end
	})
}

$pinger = Thread.new($s) { |sock|
	while true
		sleep 100
		sock.puts "PING :#{nick}"
	end
}

$output = Thread.new($s) { |socket| 
	while line = socket.gets
		if line =~ /PING :(.+)$/
			puts "PING"
			socket.puts "PONG :#{$1}"
			next
		end
		$queue << line
	end
}

$input = Thread.new($s) { |socket| 
	while line = gets
		result = "no result"
		begin
			result = (eval line).inspect
			if result.empty?
				result = "no result"
			end
		rescue Exception => err
			result = "Exception: " + err.to_s
		end
		puts result
	end

}

$output.join
$input.exit
$pinger.exit
for i in $threads
	i.exit
end
