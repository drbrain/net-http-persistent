require 'rubygems'
require 'minitest/autorun'
require 'net/http/persistent'
require 'openssl'
require 'webrick'
require 'webrick/ssl'

##
# This test is based on (and contains verbatim code from) the Net::HTTP tests
# in ruby

class TestNetHttpPersistentSSLReuse < MiniTest::Unit::TestCase

  class NullWriter
    def <<(s) end
    def puts(*args) end
    def print(*args) end
    def printf(*args) end
  end

  def setup
    @name = OpenSSL::X509::Name.parse 'CN=localhost'

    @key = OpenSSL::PKey::RSA.new 512

    @cert = OpenSSL::X509::Certificate.new
    @cert.version = 2
    @cert.serial = 0
    @cert.not_before = Time.now
    @cert.not_after = Time.now + 300
    @cert.public_key = @key.public_key
    @cert.subject = @name

    @host = 'localhost'
    @port = 10082

    config = {
      :BindAddress                => @host,
      :Port                       => @port,
      :Logger                     => WEBrick::Log.new(NullWriter.new),
      :AccessLog                  => [],
      :ShutDownSocketWithoutClose => true,
      :ServerType                 => Thread,
      :SSLEnable                  => true,
      :SSLCertificate             => @cert,
      :SSLPrivateKey              => @key,
      :SSLStartImmediately        => true,
    }

    @server = WEBrick::HTTPServer.new config

    @server.mount_proc '/' do |req, res|
      res.body = "ok"
    end

    @server.start

    begin
      TCPSocket.open(@host, @port).close
    rescue Errno::ECONNREFUSED
      sleep 0.2
      n_try_max -= 1
      raise 'cannot spawn server; give up' if n_try_max < 0
      retry
    end
  end

  def teardown
    if @server then
      @server.shutdown
      sleep 0.01 until @server.status == :Stop
    end
  end

  def test_ssl_connection_reuse
    @http = Net::HTTP::Persistent::SSLReuse.new @host, @port
    @http.use_ssl = true
    @http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    @http.verify_callback = proc do |_, store_ctx|
      store_ctx.current_cert.to_der == @cert.to_der
    end

    @http.start
    @http.get '/'
    @http.finish

    @http.start
    @http.get '/'
    @http.finish

    @http.start
    @http.get '/'

    socket = @http.instance_variable_get :@socket
    ssl_socket = socket.io

    assert ssl_socket.session_reused?
  end

end

