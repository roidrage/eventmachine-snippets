#!/usr/bin/env ruby
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
    trap(:HUP) do
      @timer.cancel
    end

    at_exit {exit!}
    @pid = EM.fork_reactor do
      $0 = "(child)\0"
      setup
      run
    end
  end

  def refork
    Process.waitpid(@pid, Process::WNOHANG) rescue Errno::ECHILD
    @connection = nil
    fork
    puts "Respawning as #{@pid}"
    @pid
  end

  def setup
    @connection = EM.connect('127.0.0.1', @port) do |c|
      class << c
        include EM::P::ObjectProtocol
      end
    end

    @timer = EM.add_periodic_timer(2) do
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

  attr_accessor :timeout, :processes

  def self.run
    new.run
  end

  def initialize
    @processes = {}
    @timeout = 10
  end

  def run
    start_server
    start_processes
    start_monitor
    set_traps
  end

  def receive_message(msg)
    message, arg = msg
    if message == :heartbeat
      puts "Ping from #{arg}"
      @processes[arg][:last_seen] = Time.now.utc
    end
  end

  def start_server
    $0 = "(master)"
    @server = EM.start_server('127.0.0.1', 0, ProcessMonitor::Server) do |c|
      c.owner = self
    end
    @port = Socket.unpack_sockaddr_in(EM.get_sockname(@server)).first
  end

  def start_processes
    [Runner, Runner, Runner, Runner, Runner].each do |runnable|
      process = SingleProcess.new(@port, runnable, {})
      pid = process.fork
      @processes[pid] = {:process => process, :last_seen => Time.now.utc}
    end
  end

  def start_monitor
    EM.add_periodic_timer(timeout) do
      check_processes
    end
  end

  def check_processes
    @processes.each do |pid, process|
      if process[:last_seen] < Time.now.utc - timeout
        puts "Process #{pid} timed out"
        respawn(pid)
      end
    end
  end

  def respawn(pid)
    process = @processes.delete(pid)[:process]
    pid = process.refork
    @processes[pid] = {:process => process, :last_seen => Time.now.utc}
  end

  def set_traps
    at_exit do
      puts "Cleaning up child processes"
      processes.each do |pid, process|
        begin
          Process.kill(:TERM, pid)
        rescue Errno::ECHILD, Errno::ESRCH
        end
      end
      puts "Done..."
      exit
    end
  end
end

EM.run do 
  trap(:INT) do
    EM.stop
  end

  ProcessMonitor.run
end
