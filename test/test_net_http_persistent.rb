require 'minitest/autorun'
require 'net/http/persistent'
require 'openssl'
require 'stringio'

class TestNetHttpPersistent < MiniTest::Unit::TestCase

  def setup
    @http = Net::HTTP::Persistent.new
    @uri  = URI.parse 'http://example.com/path'
  end

  def teardown
    Thread.current[:net_http_persistent_connections] = nil
    Thread.current[:net_http_persistent_requests] = nil
  end

  def connection
    c = Object.new
    # Net::HTTP
    def c.finish; @finish = true end
    def c.request(req) @req = req; :response end
    def c.reset; @reset = true end
    def c.start; end

    # util
    def c.req() @req; end
    def c.reset?; @reset end
    def c.started?; true end
    conns["#{@uri.host}:#{@uri.port}"] = c
    c
  end

  def conns
    Thread.current[:net_http_persistent_connections] ||= {}
  end

  def reqs
    Thread.current[:net_http_persistent_requests] ||= {}
  end

  def test_connection_for
    c = @http.connection_for @uri

    assert c.started?

    assert_includes conns.keys, 'example.com:80'
    assert_same c, conns['example.com:80']
  end

  def test_connection_for_cached
    cached = Object.new
    def cached.started?; true end
    conns['example.com:80'] = cached

    c = @http.connection_for @uri

    assert c.started?

    assert_same cached, c
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

  def test_connection_for_refused
    cached = Object.new
    def cached.address; 'example.com' end
    def cached.port; 80 end
    def cached.start; raise Errno::ECONNREFUSED end
    def cached.started?; false end
    conns['example.com:80'] = cached

    e = assert_raises Net::HTTP::Persistent::Error do
      @http.connection_for @uri
    end

    assert_match %r%connection refused%, e.message
  end

  def test_error_message
    c = Object.new
    reqs[c.object_id] = 5

    assert_equal "after 5 requests on #{c.object_id}", @http.error_message(c)
  end

  def test_reset
    c = Object.new
    def c.finish; @finished = true end
    def c.finished?; @finished end
    def c.start; @started = true end
    def c.started?; @started end
    reqs[c.object_id] = 5

    @http.reset c

    assert c.started?
    assert c.finished?
    assert_nil reqs[c.object_id]
  end

  def test_reset_io_error
    c = Object.new
    def c.finish; @finished = true; raise IOError end
    def c.finished?; @finished end
    def c.start; @started = true end
    def c.started?; @started end
    reqs[c.object_id] = 5

    @http.reset c

    assert c.started?
    assert c.finished?
  end

  def test_reset_host_down
    c = Object.new
    def c.address; 'example.com' end
    def c.finish; end
    def c.port; 80 end
    def c.start; raise Errno::EHOSTDOWN end
    reqs[c.object_id] = 5

    e = assert_raises Net::HTTP::Persistent::Error do
      @http.reset c
    end

    assert_match %r%host down%, e.message
  end

  def test_reset_refused
    c = Object.new
    def c.address; 'example.com' end
    def c.finish; end
    def c.port; 80 end
    def c.start; raise Errno::ECONNREFUSED end
    reqs[c.object_id] = 5

    e = assert_raises Net::HTTP::Persistent::Error do
      @http.reset c
    end

    assert_match %r%connection refused%, e.message
  end

  def test_request
    @http.headers['user-agent'] = 'test ua'
    c = connection

    res = @http.request @uri
    req = c.req

    assert_equal :response, res

    assert_kind_of Net::HTTP::Get, req
    assert_equal '/path',      req.path
    assert_equal 'keep-alive', req['connection']
    assert_equal '30',         req['keep-alive']
    assert_match %r%test ua%,  req['user-agent']

    assert_equal 1, reqs[c.object_id]
  end

  def test_request_bad_response
    c = connection
    def c.request(*a) raise Net::HTTPBadResponse end

    e = assert_raises Net::HTTP::Persistent::Error do
      @http.request @uri
    end

    assert_equal 0, reqs[c.object_id]
    assert_match %r%too many bad responses%, e.message
  end

  def test_request_reset
    c = connection
    def c.request(*a) raise Errno::ECONNRESET end

    e = assert_raises Net::HTTP::Persistent::Error do
      @http.request @uri
    end

    assert_equal 0, reqs[c.object_id]
    assert_match %r%too many connection resets%, e.message
  end

  def test_request_post
    c = connection

    post = Net::HTTP::Post.new @uri.path

    res = @http.request @uri, post
    req = c.req

    assert_equal :response, res

    assert_same post, req
  end

  def test_ssl
    @http.verify_callback = :callback
    c = Net::HTTP.new 'localhost', 80

    @http.ssl c

    assert c.use_ssl?
    assert_nil c.verify_mode
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

end

