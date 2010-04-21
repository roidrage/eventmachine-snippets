require 'rubygems'
require 'eventmachine'
require 'amqp'
require 'mq'
require 'mq/logger'
require 'time'
require 'logger'

class LogAggregator
  def initialize
    @log = Logger.new("/tmp/nanite.log")
    @log.formatter = Formatter.new
  end
  
  def listen
    MQ.queue('logging').bind(MQ.fanout("logging")).subscribe do |message|
      @log.send(message[:severity], message)
    end
  end

  class Formatter < Logger::Formatter
    @@format = "[%s] %s (identity: %s): %s\n"
    
    def call(severity, time, progname, message)
      @@format % [message[:timestamp].rfc2822(), severity, message[:identity], msg2str(message[:msg])]
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