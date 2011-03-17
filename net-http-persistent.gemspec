# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{net-http-persistent}
  s.version = "1.6.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Eric Hodel"]
  s.date = %q{2011-03-17}
  s.description = %q{Manages persistent connections using Net::HTTP plus a speed fix for 1.8.  It's
thread-safe too!

Using persistent HTTP connections can dramatically increase the speed of HTTP.
Creating a new HTTP connection for every request involves an extra TCP
round-trip and causes TCP congestion avoidance negotiation to start over.

Net::HTTP supports persistent connections with some API methods but does not
handle reconnection gracefully.  net-http-persistent supports reconnection
according to RFC 2616.}
  s.email = ["drbrain@segment7.net"]
  s.extra_rdoc_files = ["History.txt", "Manifest.txt", "README.txt"]
  s.files = [".autotest", ".gemtest", "History.txt", "Manifest.txt", "README.txt", "Rakefile", "lib/net/http/faster.rb", "lib/net/http/persistent.rb", "test/test_net_http_persistent.rb"]
  s.homepage = %q{http://seattlerb.rubyforge.org/net-http-persistent}
  s.rdoc_options = ["--main", "README.txt"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{net-http-persistent}
  s.rubygems_version = %q{1.6.2}
  s.summary = %q{Manages persistent connections using Net::HTTP plus a speed fix for 1.8}
  s.test_files = ["test/test_net_http_persistent.rb"]

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_development_dependency(%q<hoe>, [">= 2.9.1"])
    else
      s.add_dependency(%q<hoe>, [">= 2.9.1"])
    end
  else
    s.add_dependency(%q<hoe>, [">= 2.9.1"])
  end
end
