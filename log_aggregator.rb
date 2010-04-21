require 'rubygems'
require 'eventmachine'
require 'amqp'
require 'mq'
require 'mq/logger'
require 'time'

class LogAggregator
  @@format = "[%s] %s (identity: %s): %s\n"
  
  def initialize
    @log = File.new("/tmp/nanite.log", "a")
  end
  
  def listen
    MQ.queue('logging').bind(MQ.fanout("logging")).subscribe do |message|
      log Marshal.load(message)
    end
  end
  
  def formatted(message)
    @@format % [message[:timestamp].rfc2822(), message[:severity].to_s.upcase, message[:identity], msg2str(message[:msg])]
  end
  
  def log(message)
    @log.write(formatted(message))
  end

  def msg2str(msg)
    case msg
    when ::String
      msg
    when ::Hash
      "#{ msg[:message] } (#{ msg[:name] })\n" <<
        (msg[:backtrace] || []).join("\n")
    else
      msg.inspect
    end
  end
  
  def self.run
    new.listen
  end
end

EM.run do
  LogAggregator.run
  
  EM.add_timer(1) do
    MQ::Logger.new.debug("Agent terminated", :identity => 'k2')
    begin
      raise
    rescue
      MQ::Logger.new.error($!, :identity => 'k1')
    end
  end
end