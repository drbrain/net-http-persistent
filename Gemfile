# -*- ruby -*-

source "https://rubygems.org/"

gemspec

gem "minitest", "~>5.15", :group => [:development, :test]
gem "rdoc", ">=4.0", "<7", :group => [:development, :test]
gem "rake-manifest", "~>0.2"

gem 'net-http-pipeline', '~> 1.0' if ENV['TRAVIS_MATRIX'] == 'pipeline'

# vim: syntax=ruby
