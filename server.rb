require 'rubygems'
require 'eventmachine'
require 'json'

class SingleProcess
  def initialize(port)
    @port = port
  end

  def run
    EM.fork_reactor do
      $0 = "<child>"
      @connection = EM.connect('127.0.0.1', @port) do |c|
        class << c
          include EM::P::ObjectProtocol
        end
      end

      EM.add_periodic_timer(2) do
        if @connection.error?
          @connection.reconnect('127.0.0.1', @port)
        end
        @connection.send_object([:heartbeat, $$])
      end
    end
  end
end

class ProcessMonitor
  class Server < EM::Connection
    attr_accessor :owner
    include EM::P::ObjectProtocol

    def receive_object(object)
      owner.receive_message(object)
    end
  end

  def self.run
    new.run
  end

  def run
    start_server
    start_process
  end

  def receive_message(msg)
    puts "received message: #{msg.inspect}"
  end

  def start_server
    @server = EM.start_server('127.0.0.1', 0, ProcessMonitor::Server) do |c|
      c.owner = self
    end
    @port = Socket.unpack_sockaddr_in(EM.get_sockname(@server)).first
  end

  def start_process
    SingleProcess.new(@port).run
  end
end

EM.run do 
  trap(:INT) do
    EM.stop
  end

  ProcessMonitor.run
end
