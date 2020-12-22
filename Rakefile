# -*- ruby -*-

require 'hoe'

Hoe.plugin :bundler
Hoe.plugin :git
Hoe.plugin :minitest

Hoe.spec 'net-http-persistent' do
  developer 'Eric Hodel', 'drbrain@segment7.net'

  self.readme_file      = 'README.rdoc'
  self.extra_rdoc_files += Dir['*.rdoc']

  self.require_ruby_version '>= 2.3'

  license 'MIT'

  rdoc_locations <<
    'docs-push.seattlerb.org:/data/www/docs.seattlerb.org/net-http-persistent/'

  dependency 'connection_pool',   '~> 2.2'
  dependency 'minitest',          '~> 5.2', :development
  dependency 'hoe-bundler',       '~> 1.5', :development
  dependency 'net-http-pipeline', '~> 1.0' if
    ENV['TRAVIS_MATRIX'] == 'pipeline'
end

##
# Override Hoe::Package#install_gem that does not work with RubyGems 3

module Hoe::Package
  remove_method :install_gem
  def install_gem name, version = nil, rdoc = true
    should_not_sudo = Hoe::WINDOZE || ENV["NOSUDO"] || File.writable?(Gem.dir)
    null_dev = Hoe::WINDOZE ? "> NUL 2>&1" : "> /dev/null 2>&1"

    gem_cmd = Gem.default_exec_format % "gem"
    sudo    = "sudo "                   unless should_not_sudo
    local   = "--local"                 unless version
    version = %(--version "#{version}") if version

    cmd  = "#{sudo}#{gem_cmd} install #{local} #{name} #{version}"
    cmd += " --no-document" unless rdoc
    cmd += " #{null_dev}" unless Rake.application.options.trace

    puts cmd if Rake.application.options.trace
    result = system cmd
    Gem::Specification.reset
    result
  end
end

# vim: syntax=Ruby
