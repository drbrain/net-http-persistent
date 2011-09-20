require 'net/http'
require 'net/https'
require 'net/http/faster'
require 'uri'
require 'cgi' # for escaping

begin
  require 'net/http/pipeline'
rescue LoadError
end

##
# Persistent connections for Net::HTTP
#
# Net::HTTP::Persistent maintains persistent connections across all the
# servers you wish to talk to.  For each host:port you communicate with a
# single persistent connection is created.
#
# Multiple Net::HTTP::Persistent objects will share the same set of
# connections.
#
# For each thread you start a new connection will be created.  A
# Net::HTTP::Persistent connection will not be shared across threads.
#
# You can shut down the HTTP connections when done by calling #shutdown.  You
# should name your Net::HTTP::Persistent object if you intend to call this
# method.
#
# Example:
#
#   uri = URI.parse 'http://example.com/awesome/web/service'
#   http = Net::HTTP::Persistent.new
#   stuff = http.request uri # performs a GET
#
#   # perform a POST
#   post_uri = uri + 'create'
#   post = Net::HTTP::Post.new post_uri.path
#   post.set_form_data 'some' => 'cool data'
#   http.request post_uri, post # URI is always required

class Net::HTTP::Persistent

  ##
  # The version of Net::HTTP::Persistent use are using

  VERSION = '2.0'

  ##
  # Error class for errors raised by Net::HTTP::Persistent.  Various
  # SystemCallErrors are re-raised with a human-readable message under this
  # class.

  class Error < StandardError; end

  ##
  # This client's OpenSSL::X509::Certificate

  attr_accessor :certificate

  ##
  # An SSL certificate authority.  Setting this will set verify_mode to
  # VERIFY_PEER.

  attr_accessor :ca_file

  ##
  # An SSL certificate store. Setting this will override the default
  # certificate store. See verify_mode for more information.

  attr_accessor :cert_store

  ##
  # Where this instance's connections live in the thread local variables

  attr_reader :connection_key # :nodoc:

  ##
  # Sends debug_output to this IO via Net::HTTP#set_debug_output.
  #
  # Never use this method in production code, it causes a serious security
  # hole.

  attr_accessor :debug_output

  ##
  # Headers that are added to every request

  attr_reader :headers

  ##
  # Maps host:port to an HTTP version.  This allows us to enable version
  # specific features.

  attr_reader :http_versions

  ##
  # The value sent in the Keep-Alive header.  Defaults to 30.  Not needed for
  # HTTP/1.1 servers.
  #
  # This may not work correctly for HTTP/1.0 servers
  #
  # This method may be removed in a future version as RFC 2616 does not
  # require this header.

  attr_accessor :keep_alive

  ##
  # A name for this connection.  Allows you to keep your connections apart
  # from everybody else's.

  attr_reader :name

  ##
  # Seconds to wait until a connection is opened.  See Net::HTTP#open_timeout

  attr_accessor :open_timeout

  ##
  # This client's SSL private key

  attr_accessor :private_key

  ##
  # The URL through which requests will be proxied

  attr_reader :proxy_uri

  ##
  # Seconds to wait until reading one block.  See Net::HTTP#read_timeout

  attr_accessor :read_timeout

  ##
  # Where this instance's request counts live in the thread local variables

  attr_reader :request_key # :nodoc:

  ##
  # An array of options for Socket#setsockopt.
  #
  # By default the TCP_NODELAY option is set on sockets.
  #
  # To set additional options append them to this array:
  #
  #   http.socket_options << [Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, 1]

  attr_reader :socket_options

  ##
  # SSL verification callback.  Used when ca_file is set.

  attr_accessor :verify_callback

  ##
  # HTTPS verify mode.  Defaults to OpenSSL::SSL::VERIFY_PEER which verifies
  # the server certificate.
  #
  # If no certificate, ca_file or cert_store is set the default system
  # certificate store is used.
  #
  # To disable server certificate validation set to OpenSSL::SSL::VERIFY_NONE,
  # but this is a bad idea as it disables SSL protections.
  #
  # You can use +verify_mode+ to override any default values.

  attr_accessor :verify_mode

  ##
  # Enable retries of non-idempotent requests that change data (e.g. POST
  # requests) when the server has disconnected.
  #
  # This will in the worst case lead to multiple requests with the same data,
  # but it may be useful for some applications.  Take care when enabling
  # this option to ensure it is safe to POST or perform other non-idempotent
  # requests to the server.

  attr_accessor :retry_change_requests

  ##
  # Creates a new Net::HTTP::Persistent.
  #
  # Set +name+ to keep your connections apart from everybody else's.  Not
  # required currently, but highly recommended.  Your library name should be
  # good enough.  This parameter will be required in a future version.
  #
  # +proxy+ may be set to a URI::HTTP or :ENV to pick up proxy options from
  # the environment.  See proxy_from_env for details.
  #
  # In order to use a URI for the proxy you'll need to do some extra work
  # beyond URI.parse:
  #
  #   proxy = URI.parse 'http://proxy.example'
  #   proxy.user     = 'AzureDiamond'
  #   proxy.password = 'hunter2'

  def initialize name = nil, proxy = nil
    @name = name

    @proxy_uri = case proxy
                 when :ENV      then proxy_from_env
                 when URI::HTTP then proxy
                 when nil       then # ignore
                 else raise ArgumentError, 'proxy must be :ENV or a URI::HTTP'
                 end

    if @proxy_uri then
      @proxy_args = [
        @proxy_uri.host,
        @proxy_uri.port,
        @proxy_uri.user,
        @proxy_uri.password,
      ]

      @proxy_connection_id = [nil, *@proxy_args].join ':'
    end

    @debug_output   = nil
    @headers        = {}
    @http_versions  = {}
    @keep_alive     = 30
    @open_timeout   = nil
    @read_timeout   = nil
    @socket_options = []

    @socket_options << [Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1] if
      Socket.const_defined? :TCP_NODELAY

    key = ['net_http_persistent', name, 'connections'].compact.join '_'
    @connection_key = key.intern
    key = ['net_http_persistent', name, 'requests'].compact.join '_'
    @request_key    = key.intern

    @certificate     = nil
    @ca_file         = nil
    @private_key     = nil
    @verify_callback = nil
    @verify_mode     = nil
    @cert_store      = nil

    @retry_change_requests = false
  end

  ##
  # Creates a new connection for +uri+

  def connection_for uri
    Thread.current[@connection_key] ||= {}
    Thread.current[@request_key]    ||= Hash.new 0

    connections = Thread.current[@connection_key]

    net_http_args = [uri.host, uri.port]
    connection_id = net_http_args.join ':'

    if @proxy_uri then
      connection_id << @proxy_connection_id
      net_http_args.concat @proxy_args
    end

    unless connection = connections[connection_id] then
      connections[connection_id] = Net::HTTP.new(*net_http_args)
      connection = connections[connection_id]
      ssl connection if uri.scheme.downcase == 'https'
    end

    unless connection.started? then
      connection.set_debug_output @debug_output if @debug_output
      connection.open_timeout = @open_timeout if @open_timeout
      connection.read_timeout = @read_timeout if @read_timeout

      connection.start

      socket = connection.instance_variable_get :@socket

      if socket then # for fakeweb
        @socket_options.each do |option|
          socket.io.setsockopt(*option)
        end
      end
    end

    connection
  rescue Errno::ECONNREFUSED
    raise Error, "connection refused: #{connection.address}:#{connection.port}"
  rescue Errno::EHOSTDOWN
    raise Error, "host down: #{connection.address}:#{connection.port}"
  end

  ##
  # Returns an error message containing the number of requests performed on
  # this connection

  def error_message connection
    requests =
      Thread.current[@request_key][connection.object_id]

    "after #{requests} requests on #{connection.object_id}"
  end

  ##
  # URI::escape wrapper

  def escape str
    CGI.escape str if str
  end

  ##
  # Finishes the Net::HTTP +connection+

  def finish connection
    Thread.current[@request_key].delete connection.object_id

    connection.finish
  rescue IOError
  end

  ##
  # Returns the HTTP protocol version for +uri+

  def http_version uri
    @http_versions["#{uri.host}:#{uri.port}"]
  end

  ##
  # Is +req+ idempotent according to RFC 2616?

  def idempotent? req
    case req
    when Net::HTTP::Delete, Net::HTTP::Get, Net::HTTP::Head,
         Net::HTTP::Options, Net::HTTP::Put, Net::HTTP::Trace then
      true
    end
  end

  ##
  # Is the request idempotent or is retry_change_requests allowed

  def can_retry? req
    retry_change_requests or idempotent?(req)
  end

  ##
  # Adds "http://" to the String +uri+ if it is missing.

  def normalize_uri uri
    (uri =~ /^https?:/) ? uri : "http://#{uri}"
  end

  ##
  # Pipelines +requests+ to the HTTP server at +uri+ yielding responses if a
  # block is given.  Returns all responses recieved.
  #
  # See
  # Net::HTTP::Pipeline[http://docs.seattlerb.org/net-http-pipeline/Net/HTTP/Pipeline.html]
  # for further details.
  #
  # Only if <tt>net-http-pipeline</tt> was required before
  # <tt>net-http-persistent</tt> #pipeline will be present.

  def pipeline uri, requests, &block # :yields: responses
    connection = connection_for uri

    connection.pipeline requests, &block
  end

  ##
  # Creates a URI for an HTTP proxy server from ENV variables.
  #
  # If +HTTP_PROXY+ is set a proxy will be returned.
  #
  # If +HTTP_PROXY_USER+ or +HTTP_PROXY_PASS+ are set the URI is given the
  # indicated user and password unless HTTP_PROXY contains either of these in
  # the URI.
  #
  # For Windows users lowercase ENV variables are preferred over uppercase ENV
  # variables.

  def proxy_from_env
    env_proxy = ENV['http_proxy'] || ENV['HTTP_PROXY']

    return nil if env_proxy.nil? or env_proxy.empty?

    uri = URI.parse normalize_uri env_proxy

    unless uri.user or uri.password then
      uri.user     = escape ENV['http_proxy_user'] || ENV['HTTP_PROXY_USER']
      uri.password = escape ENV['http_proxy_pass'] || ENV['HTTP_PROXY_PASS']
    end

    uri
  end

  ##
  # Finishes then restarts the Net::HTTP +connection+

  def reset connection
    Thread.current[@request_key].delete connection.object_id

    finish connection

    connection.start
  rescue Errno::ECONNREFUSED
    raise Error, "connection refused: #{connection.address}:#{connection.port}"
  rescue Errno::EHOSTDOWN
    raise Error, "host down: #{connection.address}:#{connection.port}"
  end

  ##
  # Makes a request on +uri+.  If +req+ is nil a Net::HTTP::Get is performed
  # against +uri+.
  #
  # If a block is passed #request behaves like Net::HTTP#request (the body of
  # the response will not have been read).
  #
  # +req+ must be a Net::HTTPRequest subclass (see Net::HTTP for a list).
  #
  # If there is an error and the request is idempontent according to RFC 2616
  # it will be retried automatically.

  def request uri, req = nil, &block
    retried      = false
    bad_response = false

    req = Net::HTTP::Get.new uri.request_uri unless req

    headers.each do |pair|
      req.add_field(*pair)
    end

    req.add_field 'Connection', 'keep-alive'
    req.add_field 'Keep-Alive', @keep_alive

    connection = connection_for uri
    connection_id = connection.object_id

    begin
      Thread.current[@request_key][connection_id] += 1
      response = connection.request req, &block

    rescue Net::HTTPBadResponse => e
      message = error_message connection

      finish connection

      raise Error, "too many bad responses #{message}" if
        bad_response or not can_retry? req

      bad_response = true
      retry
    rescue IOError, EOFError, Timeout::Error,
           Errno::ECONNABORTED, Errno::ECONNRESET, Errno::EPIPE,
           Errno::EINVAL, OpenSSL::SSL::SSLError => e

      if retried or not can_retry? req
        due_to = "(due to #{e.message} - #{e.class})"
        message = error_message connection

        finish connection

        raise Error, "too many connection resets #{due_to} #{message}"
      end

      reset connection

      retried = true
      retry
    end

    @http_versions["#{uri.host}:#{uri.port}"] ||= response.http_version

    response
  end

  ##
  # Shuts down all connections for +thread+.
  #
  # Uses the current thread by default.
  #
  # If you've used Net::HTTP::Persistent across multiple threads you should
  # call this in each thread when you're done making HTTP requests.
  #
  # *NOTE*: Calling shutdown for another thread can be dangerous!
  #
  # If the thread is still using the connection it may cause an error!  It is
  # best to call #shutdown in the thread at the appropriate time instead!

  def shutdown thread = Thread.current
    connections = thread[@connection_key]

    connections.each do |_, connection|
      begin
        connection.finish
      rescue IOError
      end
    end if connections

    thread[@connection_key] = nil
    thread[@request_key]    = nil
  end

  ##
  # Shuts down all connections in all threads
  #
  # *NOTE*: THIS METHOD IS VERY DANGEROUS!
  #
  # Do not call this method if other threads are still using their
  # connections!  Call #shutdown at the appropriate time instead!
  #
  # Use this method only as a last resort!

  def shutdown_in_all_threads
    Thread.list.each do |thread|
      shutdown thread
    end

    nil
  end

  ##
  # Enables SSL on +connection+

  def ssl connection
    connection.use_ssl = true

    connection.verify_mode = @verify_mode || OpenSSL::SSL::VERIFY_PEER

    if @ca_file then
      connection.ca_file = @ca_file
      connection.verify_mode = OpenSSL::SSL::VERIFY_PEER
      connection.verify_callback = @verify_callback if @verify_callback
    end

    if @certificate and @private_key then
      connection.cert = @certificate
      connection.key  = @private_key
    end

    connection.cert_store = if @cert_store    
      @cert_store
    else
      store = OpenSSL::X509::Store.new
      store.set_default_paths
      store
    end
  end

end

