require 'rubygems'
require 'minitest/autorun'
require 'net/http/persistent'
require 'openssl'
require 'stringio'

class Net::HTTP
  alias orig_connect connect

  def connect
    unless use_ssl? then
      io = Object.new
      def io.setsockopt(*a) @setsockopts ||= []; @setsockopts << a end

      @socket = Net::BufferedIO.new io

      return
    end

    io = open '/dev/null'
    def io.setsockopt(*a) @setsockopts ||= []; @setsockopts << a end

    @ssl_context ||= OpenSSL::SSL::SSLContext.new

    @ssl_context.verify_mode = OpenSSL::SSL::VERIFY_PEER unless
      @ssl_context.verify_mode

    s = OpenSSL::SSL::SSLSocket.new io, @ssl_context

    @socket = Net::BufferedIO.new s
  end
end

class TestNetHttpPersistent < MiniTest::Unit::TestCase

  def setup
    @http = Net::HTTP::Persistent.new
    @uri  = URI.parse 'http://example.com/path'

    ENV.delete 'http_proxy'
    ENV.delete 'HTTP_PROXY'
    ENV.delete 'http_proxy_user'
    ENV.delete 'HTTP_PROXY_USER'
    ENV.delete 'http_proxy_pass'
    ENV.delete 'HTTP_PROXY_PASS'
  end

  def teardown
    Thread.current.keys.each do |key|
      Thread.current[key] = nil
    end
  end

  class BasicConnection
    attr_accessor :started, :finished, :address, :port
    attr_reader :req
    def initialize
      @started, @finished = 0, 0
      @address, @port = 'example.com', 80
    end
    def finish
      @finished += 1
      @socket = nil
    end
    def finished?
      @finished >= 1
    end
    def pipeline requests, &block
      requests.map { |r| r.path }
    end
    def reset?
      @started == @finished + 1
    end
    def start
      @started += 1
      io = Object.new
      def io.setsockopt(*a) @setsockopts ||= []; @setsockopts << a end
      @socket = Net::BufferedIO.new io
    end
    def started?
      @started >= 1
    end
  end

  def basic_connection
    c = BasicConnection.new
    conns["#{@uri.host}:#{@uri.port}"] = c
    c
  end

  def connection
    c = basic_connection

    def c.request(req)
      @req = req
      r = Net::HTTPResponse.allocate
      def r.http_version() '1.1' end
      def r.read_body() :read_body end
      yield r if block_given?
      r
    end

    c
  end

  def conns
    Thread.current[@http.connection_key] ||= {}
  end

  def reqs
    Thread.current[@http.request_key] ||= {}
  end

  def test_initialize
    assert_nil @http.proxy_uri
  end

  def test_initialize_name
    http = Net::HTTP::Persistent.new 'name'
    assert_equal 'name', http.name
  end

  def test_initialize_env
    ENV['HTTP_PROXY'] = 'proxy.example'
    http = Net::HTTP::Persistent.new nil, :ENV

    assert_equal URI.parse('http://proxy.example'), http.proxy_uri
  end

  def test_initialize_uri
    proxy_uri = URI.parse 'http://proxy.example'

    http = Net::HTTP::Persistent.new nil, proxy_uri

    assert_equal proxy_uri, http.proxy_uri
  end

  def test_connection_for
    @http.open_timeout = 123
    @http.read_timeout = 321
    c = @http.connection_for @uri

    assert c.started?
    refute c.proxy?

    assert_equal 123, c.open_timeout
    assert_equal 321, c.read_timeout

    assert_includes conns.keys, 'example.com:80'
    assert_same c, conns['example.com:80']

    socket = c.instance_variable_get :@socket
    expected = if Socket.const_defined? :TCP_NODELAY then
                 [[Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1]]
               else
                 []
               end

    assert_equal expected, socket.io.instance_variable_get(:@setsockopts)
  end

  def test_connection_for_cached
    cached = basic_connection
    cached.start
    conns['example.com:80'] = cached

    c = @http.connection_for @uri

    assert c.started?

    assert_same cached, c
  end

  def test_connection_for_closed
    cached = basic_connection
    cached.start
    if Socket.const_defined? :TCP_NODELAY then
      def (cached.instance_variable_get(:@socket).io).setsockopt(*a)
        raise IOError, 'closed stream'
      end
    end
    conns['example.com:80'] = cached

    c = @http.connection_for @uri

    assert c.started?

    assert_includes conns.keys, 'example.com:80'
    assert_same c, conns['example.com:80']

    socket = c.instance_variable_get :@socket
    assert_nil socket.io.instance_variable_get(:@setsockopt)
  end

  def test_connection_for_debug_output
    io = StringIO.new
    @http.debug_output = io

    c = @http.connection_for @uri

    assert c.started?
    assert_equal io, c.instance_variable_get(:@debug_output)

    assert_includes conns.keys, 'example.com:80'
    assert_same c, conns['example.com:80']
  end

  def test_connection_for_finished_ssl
    uri = URI.parse 'https://example.com/path'
    c = @http.connection_for uri

    assert c.started?
    assert c.use_ssl?

    @http.finish c

    refute c.started?

    c2 = @http.connection_for uri

    assert c2.started?
  end

  def test_connection_for_host_down
    cached = basic_connection
    def cached.start; raise Errno::EHOSTDOWN end
    def cached.started?; false end
    conns['example.com:80'] = cached

    e = assert_raises Net::HTTP::Persistent::Error do
      @http.connection_for @uri
    end

    assert_match %r%host down%, e.message
  end

  def test_connection_for_name
    http = Net::HTTP::Persistent.new 'name'
    uri = URI.parse 'http://example/'

    c = http.connection_for uri

    assert c.started?

    refute_includes conns.keys, 'example:80'
  end

  def test_connection_for_proxy
    uri = URI.parse 'http://proxy.example'
    uri.user     = 'johndoe'
    uri.password = 'muffins'

    http = Net::HTTP::Persistent.new nil, uri

    c = http.connection_for @uri

    assert c.started?
    assert c.proxy?

    assert_includes conns.keys,
                    'example.com:80:proxy.example:80:johndoe:muffins'
    assert_same c, conns['example.com:80:proxy.example:80:johndoe:muffins']
  end

  def test_connection_for_refused
    cached = basic_connection
    def cached.start; raise Errno::ECONNREFUSED end
    def cached.started?; false end
    conns['example.com:80'] = cached

    e = assert_raises Net::HTTP::Persistent::Error do
      @http.connection_for @uri
    end

    assert_match %r%connection refused%, e.message
  end

  def test_connection_for_socket_options
    @http.socket_options << [Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, 1]
    c = @http.connection_for @uri

    socket = c.instance_variable_get :@socket

    expected = []
    expected << [Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1] if
      Socket.const_defined? :TCP_NODELAY
    expected << [Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, 1]

    assert_equal expected, socket.io.instance_variable_get(:@setsockopts)
  end

  def test_connection_for_ssl
    uri = URI.parse 'https://example.com/path'
    c = @http.connection_for uri

    assert c.started?
    assert c.use_ssl?
  end

  def test_connection_for_ssl_case
    uri = URI.parse 'HTTPS://example.com/path'
    c = @http.connection_for uri

    assert c.started?
    assert c.use_ssl?
  end

  def test_error_message
    c = basic_connection
    reqs[c.object_id] = 5

    assert_equal "after 5 requests on #{c.object_id}", @http.error_message(c)
  end

  def test_escape
    assert_nil @http.escape nil

    assert_equal '+%3F', @http.escape(' ?')
  end

  def test_finish
    c = basic_connection
    reqs[c.object_id] = 5

    @http.finish c

    refute c.started?
    assert c.finished?
    assert_nil reqs[c.object_id]
  end

  def test_finish_io_error
    c = basic_connection
    def c.finish; @finished += 1; raise IOError end
    reqs[c.object_id] = 5

    @http.finish c

    refute c.started?
    assert c.finished?
  end

  def test_http_version
    assert_nil @http.http_version @uri

    connection

    @http.request @uri

    assert_equal '1.1', @http.http_version(@uri)
  end

  def test_idempotent_eh
    assert @http.idempotent? Net::HTTP::Delete.new '/'
    assert @http.idempotent? Net::HTTP::Get.new '/'
    assert @http.idempotent? Net::HTTP::Head.new '/'
    assert @http.idempotent? Net::HTTP::Options.new '/'
    assert @http.idempotent? Net::HTTP::Put.new '/'
    assert @http.idempotent? Net::HTTP::Trace.new '/'

    refute @http.idempotent? Net::HTTP::Post.new '/'
  end

  def test_normalize_uri
    assert_equal 'http://example',  @http.normalize_uri('example')
    assert_equal 'http://example',  @http.normalize_uri('http://example')
    assert_equal 'https://example', @http.normalize_uri('https://example')
  end

  def test_pipeline
    skip 'net-http-pipeline not installed' unless defined?(Net::HTTP::Pipeline)

    cached = basic_connection
    cached.start
    conns['example.com:80'] = cached

    requests = [
      Net::HTTP::Get.new((@uri + '1').request_uri),
      Net::HTTP::Get.new((@uri + '2').request_uri),
    ]

    responses = @http.pipeline @uri, requests

    assert_equal 2, responses.length
    assert_equal '/1', responses.first
    assert_equal '/2', responses.last
  end

  def test_proxy_from_env
    ENV['HTTP_PROXY']      = 'proxy.example'
    ENV['HTTP_PROXY_USER'] = 'johndoe'
    ENV['HTTP_PROXY_PASS'] = 'muffins'

    uri = @http.proxy_from_env

    expected = URI.parse 'http://proxy.example'
    expected.user     = 'johndoe'
    expected.password = 'muffins'

    assert_equal expected, uri
  end

  def test_proxy_from_env_lower
    ENV['http_proxy']      = 'proxy.example'
    ENV['http_proxy_user'] = 'johndoe'
    ENV['http_proxy_pass'] = 'muffins'

    uri = @http.proxy_from_env

    expected = URI.parse 'http://proxy.example'
    expected.user     = 'johndoe'
    expected.password = 'muffins'

    assert_equal expected, uri
  end

  def test_proxy_from_env_nil
    uri = @http.proxy_from_env

    assert_nil uri

    ENV['HTTP_PROXY'] = ''

    uri = @http.proxy_from_env

    assert_nil uri
  end

  def test_reset
    c = basic_connection
    c.start
    reqs[c.object_id] = 5

    @http.reset c

    assert c.started?
    assert c.finished?
    assert c.reset?
    assert_nil reqs[c.object_id]
  end

  def test_reset_io_error
    c = basic_connection
    reqs[c.object_id] = 5

    @http.reset c

    assert c.started?
    assert c.finished?
  end

  def test_reset_host_down
    c = basic_connection
    def c.start; raise Errno::EHOSTDOWN end
    reqs[c.object_id] = 5

    e = assert_raises Net::HTTP::Persistent::Error do
      @http.reset c
    end

    assert_match %r%host down%, e.message
  end

  def test_reset_refused
    c = basic_connection
    def c.start; raise Errno::ECONNREFUSED end
    reqs[c.object_id] = 5

    e = assert_raises Net::HTTP::Persistent::Error do
      @http.reset c
    end

    assert_match %r%connection refused%, e.message
  end

  def test_ssl_error
    uri = URI.parse 'https://example.com/path'
    c = @http.connection_for uri
    def c.request(*)
      raise OpenSSL::SSL::SSLError, "SSL3_WRITE_PENDING:bad write retry"
    end

    e = assert_raises Net::HTTP::Persistent::Error do
      @http.request uri
    end
    assert_match %r%bad write retry%, e.message
  end

  def test_request
    @http.headers['user-agent'] = 'test ua'
    c = connection

    res = @http.request @uri
    req = c.req

    assert_kind_of Net::HTTPResponse, res

    assert_kind_of Net::HTTP::Get, req
    assert_equal '/path',      req.path
    assert_equal 'keep-alive', req['connection']
    assert_equal '30',         req['keep-alive']
    assert_match %r%test ua%,  req['user-agent']

    assert_equal 1, reqs[c.object_id]
  end

  def test_request_bad_response
    c = basic_connection
    def c.request(*a) raise Net::HTTPBadResponse end

    e = assert_raises Net::HTTP::Persistent::Error do
      @http.request @uri
    end

    assert_equal 0, reqs[c.object_id]
    assert_match %r%too many bad responses%, e.message
  end

  def test_request_bad_response_retry
    c = basic_connection
    def c.request(*a)
      if defined? @called then
        Net::HTTPResponse.allocate
      else
        @called = true
        raise Net::HTTPBadResponse
      end
    end

    @http.request @uri

    assert c.finished?
  end

  def test_request_bad_response_unsafe
    c = basic_connection
    def c.request(*a)
      if instance_variable_defined? :@request then
        raise 'POST must not be retried'
      else
        @request = true
        raise Net::HTTPBadResponse
      end
    end

    e = assert_raises Net::HTTP::Persistent::Error do
      @http.request @uri, Net::HTTP::Post.new(@uri.path)
    end

    assert_equal 0, reqs[c.object_id]
    assert_match %r%too many bad responses%, e.message
  end

  def test_request_block
    @http.headers['user-agent'] = 'test ua'
    c = connection
    body = nil

    res = @http.request @uri do |r|
      body = r.read_body
    end

    req = c.req

    assert_kind_of Net::HTTPResponse, res
    refute_nil body

    assert_kind_of Net::HTTP::Get, req
    assert_equal '/path',      req.path
    assert_equal 'keep-alive', req['connection']
    assert_equal '30',         req['keep-alive']
    assert_match %r%test ua%,  req['user-agent']

    assert_equal 1, reqs[c.object_id]
  end

  def test_request_invalid
    c = basic_connection
    def c.request(*a) raise Errno::EINVAL, "write" end

    e = assert_raises Net::HTTP::Persistent::Error do
      @http.request @uri
    end

    assert_equal 0, reqs[c.object_id]
    assert_match %r%too many connection resets%, e.message
  end

  def test_request_invalid_retry
    c = basic_connection
    def c.request(*a)
      if defined? @called then
        Net::HTTPResponse.allocate
      else
        @called = true
        raise Errno::EINVAL, "write"
      end
    end

    @http.request @uri

    assert c.reset?
    assert c.finished?
  end

  def test_request_reset
    c = basic_connection
    def c.request(*a) raise Errno::ECONNRESET end

    e = assert_raises Net::HTTP::Persistent::Error do
      @http.request @uri
    end

    assert_equal 0, reqs[c.object_id]
    assert_match %r%too many connection resets%, e.message
  end

  def test_request_reset_retry
    c = basic_connection
    def c.request(*a)
      if defined? @called then
        Net::HTTPResponse.allocate
      else
        @called = true
        raise Errno::ECONNRESET
      end
    end

    @http.request @uri

    assert c.reset?
    assert c.finished?
  end

  def test_request_reset_unsafe
    c = basic_connection
    def c.request(*a)
      if instance_variable_defined? :@request then
        raise 'POST must not be retried'
      else
        @request = true
        raise Errno::ECONNRESET
      end
    end

    e = assert_raises Net::HTTP::Persistent::Error do
      @http.request @uri, Net::HTTP::Post.new(@uri.path)
    end

    assert_equal 0, reqs[c.object_id]
    assert_match %r%too many connection resets%, e.message
  end

  def test_request_post
    c = connection

    post = Net::HTTP::Post.new @uri.path

    @http.request @uri, post
    req = c.req

    assert_same post, req
  end

  def test_shutdown
    c = connection
    cs = conns
    rs = reqs

    orig = @http
    @http = Net::HTTP::Persistent.new 'name'
    c2 = connection

    orig.shutdown

    assert c.finished?
    refute c2.finished?

    refute_same cs, conns
    refute_same rs, reqs
  end

  def test_shutdown_not_started
    c = basic_connection
    def c.finish() raise IOError end

    conns["#{@uri.host}:#{@uri.port}"] = c

    @http.shutdown

    assert_nil Thread.current[@http.connection_key]
    assert_nil Thread.current[@http.request_key]
  end

  def test_shutdown_no_connections
    @http.shutdown

    assert_nil Thread.current[@http.connection_key]
    assert_nil Thread.current[@http.request_key]
  end

  def test_shutdown_thread
    t = Thread.new do
      c = connection
      conns
      reqs

      Thread.stop

      c
    end

    Thread.pass until t.status == 'sleep'

    c = connection

    @http.shutdown t

    refute c.finished?

    t.run
    assert t.value.finished?
    assert_nil t[@http.connection_key]
    assert_nil t[@http.request_key]
  end

  def test_shutdown_in_all_threads
    t = Thread.new do
      c = connection
      conns
      reqs

      Thread.stop

      c
    end

    Thread.pass until t.status == 'sleep'

    c = connection

    assert_nil @http.shutdown_in_all_threads

    assert c.finished?
    assert_nil Thread.current[@http.connection_key]
    assert_nil Thread.current[@http.request_key]

    t.run
    assert t.value.finished?
    assert_nil t[@http.connection_key]
    assert_nil t[@http.request_key]
  end

  def test_ssl
    @http.verify_callback = :callback
    c = Net::HTTP.new 'localhost', 80

    @http.ssl c

    assert c.use_ssl?
    assert_equal OpenSSL::SSL::VERIFY_NONE, c.verify_mode
    assert_nil c.verify_callback
  end

  def test_ssl_ca_file
    @http.ca_file = 'ca_file'
    @http.verify_callback = :callback
    c = Net::HTTP.new 'localhost', 80

    @http.ssl c

    assert c.use_ssl?
    assert_equal OpenSSL::SSL::VERIFY_PEER, c.verify_mode
    assert_equal :callback, c.verify_callback
  end

  def test_ssl_cert_store
    store = OpenSSL::X509::Store.new
    @http.cert_store = store

    c = Net::HTTP.new 'localhost', 80

    @http.ssl c

    assert c.use_ssl?
    assert_equal store, c.cert_store
  end

  def test_default_cert_store
    @http.verify_mode = OpenSSL::SSL::VERIFY_PEER

    c = Net::HTTP.new 'localhost', 80

    @http.ssl c

    assert c.use_ssl?
    assert c.cert_store
  end

  def test_ssl_certificate
    @http.certificate = :cert
    @http.private_key = :key
    c = Net::HTTP.new 'localhost', 80

    @http.ssl c

    assert c.use_ssl?
    assert_equal :cert, c.cert
    assert_equal :key,  c.key
  end

  def test_ssl_verify_mode
    @http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    c = Net::HTTP.new 'localhost', 80

    @http.ssl c

    assert c.use_ssl?
    assert_equal OpenSSL::SSL::VERIFY_NONE, c.verify_mode
  end

  def test_can_retry_change_requests
    get  = Net::HTTP::Get.new('/')
    post = Net::HTTP::Post.new('/')
    assert @http.can_retry?(get)
    refute @http.retry_change_requests
    refute @http.can_retry?(post)
    @http.retry_change_requests = true
    assert @http.can_retry?(get)
    assert @http.retry_change_requests
    assert @http.can_retry?(post)
  end

end

