require 'rubygems'
require 'eventmachine'
require 'json'

class Runner
  def initialize(options = {})
  end

  def run
    puts "Running!"
  end
end

class SingleProcess
  def initialize(port, runnable, options = {})
    @port = port
    @runnable = runnable
    @options = options
  end

  def fork
    EM.fork_reactor do
      $0 = "<child>\0"
      setup
      run
    end
  end

  def setup
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

  def run
    @runnable.new(@options).run
  end
end

class ProcessMonitor
  class Server < EM::Connection
    include EM::P::ObjectProtocol
    attr_accessor :owner

    def receive_object(object)
      owner.receive_message(object)
    end
  end

  def self.run
    new.run
  end

  def run
    start_server
    start_processes
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

  def start_processes
    SingleProcess.new(@port, Runner, {}).run
  end
end

EM.run do 
  trap(:INT) do
    EM.stop
  end

  ProcessMonitor.run
end
