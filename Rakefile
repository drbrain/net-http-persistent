# -*- ruby -*-

require 'rubygems'
require 'hoe'

Hoe.plugin :git
Hoe.plugin :minitest
Hoe.plugin :travis

Hoe.spec 'net-http-persistent' do |p|
  developer 'Eric Hodel', 'drbrain@segment7.net'

  self.readme_file      = 'README.rdoc'
  self.extra_rdoc_files += Dir['*.rdoc']

  rdoc_locations <<
    'docs.seattlerb.org:/data/www/docs.seattlerb.org/net-http-persistent/'
end

# vim: syntax=Ruby
