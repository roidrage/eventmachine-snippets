require 'rubygems'
require 'eventmachine'
require 'em-redis'
require 'em-http'

$url_list = 'em:urls'

$urls = %w{http://localhost/ http://www.google.de/} * 200

$count = 0

class UrlMonitor
  def initialize
    @redis = EM::Protocols::Redis.connect
    @redis.del($url_list)
    
    EM.add_timer(1) {
      EM.defer {
        redis2 = EM::Protocols::Redis.connect
        $urls.each do |url|
          redis2.lpush($url_list, url)
        end
      }
    }

    pop
  end
  
  def pop
    popper = lambda do
      @redis.brpop($url_list, 0) {|value|
        watch(value.last)
        EM.next_tick(popper)
      }
    end
    EM.next_tick(popper)
  end
  
  def warn(url, http)
    puts "URL #{url} had #{http.response_header.status}"
  end
  
  def watch(url)
    http = EventMachine::HttpRequest.new(url).get :timeout => 20
    http.errback {
    }

    http.callback {
      EM.next_tick {$count+=1}
      warn(url, http) if http.response_header.status >= 400
    }
  end
end

EM.kqueue
EM.run {
  UrlMonitor.new

  EM.add_timer(40) {
    puts "Plowed through #{$count} urls"
    EM.stop
  }
}

