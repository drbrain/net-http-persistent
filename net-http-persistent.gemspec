Gem::Specification.new 'net-http-persistent', '3.0.1' do |s|
  s.summary = "Manages persistent connections using Net::HTTP"
  s.description = "Manages persistent connections using Net::HTTP. It's thread-safe too! Using persistent HTTP connections can dramatically increase the speed of HTTP. Creating a new HTTP connection for every request involves an extra TCP round-trip and causes TCP congestion avoidance negotiation to start over. Net::HTTP supports persistent connections with some API methods but does not handle reconnection gracefully. Net::HTTP::Persistent supports reconnection and retry according to RFC 2616."
  s.authors = ["Eric Hodel"]
  s.email = "drbrain@segment7.net"
  s.homepage = "https://github.com/drbrain/net-http-persistent"
  s.files = `git ls-files lib History.txt Readme.rdoc`.split("\n")
  s.license = "MIT"
  s.required_ruby_version = '~> 2.1'
  s.add_runtime_dependency 'connection_pool', '~> 2.2'
end
