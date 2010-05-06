require 'net/http'
require 'net/http/faster'
require 'uri'

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
# Example:
#
#   uri = URI.parse 'http://example.com/awesome/web/service'
#   http = Net::HTTP::Persistent
#   stuff = http.request uri # performs a GET
#
#   # perform a POST
#   post_uri = uri + 'create'
#   post = Net::HTTP::Post.new uri.path
#   post.set_form_data 'some' => 'cool data'
#   http.request post_uri, post # URI is always required

class Net::HTTP::Persistent

  ##
  # The version of Net::HTTP::Persistent use are using

  VERSION = '1.0.1'

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
  # Sends debug_output to this IO via Net::HTTP#set_debug_output.
  #
  # Never use this method in production code, it causes a serious security
  # hole.

  attr_accessor :debug_output

  ##
  # Headers that are added to every request

  attr_reader :headers

  ##
  # The value sent in the Keep-Alive header.  Defaults to 30 seconds

  attr_accessor :keep_alive

  ##
  # This client's SSL private key

  attr_accessor :private_key

  ##
  # SSL verification callback.  Used when ca_file is set.

  attr_accessor :verify_callback

  ##
  # HTTPS verify mode.  Set to OpenSSL::SSL::VERIFY_NONE to ignore certificate
  # problems.
  #
  # You can use +verify_mode+ to override any default values.

  attr_accessor :verify_mode

  def initialize # :nodoc:
    @debug_output = nil
    @headers      = {}
    @keep_alive   = 30

    @certificate     = nil
    @ca_file         = nil
    @private_key     = nil
    @verify_callback = nil
    @verify_mode     = nil
  end

  ##
  # Creates a new connection for +uri+

  def connection_for uri
    Thread.current[:net_http_persistent_connections] ||= {}
    connections = Thread.current[:net_http_persistent_connections]

    connection_id = [uri.host, uri.port].join ':'

    connections[connection_id] ||= Net::HTTP.new uri.host, uri.port
    connection = connections[connection_id]

    connection.set_debug_output @debug_output if @debug_output

    ssl connection if uri.scheme == 'https' and not connection.started?

    connection.start unless connection.started?

    connection
  rescue Errno::ECONNREFUSED
    raise Error, "connection refused: #{connection.address}:#{connection.port}"
  end

  ##
  # Returns an error message containing the number of requests performed on
  # this connection

  def error_message connection
    requests =
      Thread.current[:net_http_persistent_requests][connection.object_id]

    "after #{requests} requests on #{connection.object_id}"
  end

  ##
  # Finishes then restarts the Net::HTTP +connection+

  def reset connection
    Thread.current[:net_http_persistent_requests].delete connection.object_id

    begin
      connection.finish
    rescue IOError
    end

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
  # +req+ must be a Net::HTTPRequest subclass (see Net::HTTP for a list).

  def request uri, req = nil
    Thread.current[:net_http_persistent_requests] ||= Hash.new 0
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
      count = Thread.current[:net_http_persistent_requests][connection_id] += 1
      response = connection.request req

    rescue Net::HTTPBadResponse => e
      message = error_message connection

      reset connection

      raise Error, "too many bad responses #{message}" if bad_response

      bad_response = true
      retry
    rescue IOError, EOFError, Timeout::Error,
           Errno::ECONNABORTED, Errno::ECONNRESET, Errno::EPIPE => e
      due_to = "(due to #{e.message} - #{e.class})"
      message = error_message connection

      reset connection

      raise Error, "too many connection resets #{due_to} #{message}" if retried

      retried = true
      retry
    end

    response
  end

  ##
  # Enables SSL on +connection+

  def ssl connection
    require 'net/https'
    connection.use_ssl = true

    if @ca_file then
      connection.ca_file = @ca_file
      connection.verify_mode = OpenSSL::SSL::VERIFY_PEER
      connection.verify_callback = @verify_callback if @verify_callback
    end

    if @certificate and @private_key then
      connection.cert = @certificate
      connection.key  = @private_key
    end

    connection.verify_mode = @verify_mode if @verify_mode
  end

end

