require 'thread'

class Net::HTTP::Persistent::Pool

  ##
  # Create a new connection pool of size +size+. If +size+ is nil, this will
  # act like a thread safe pool.

  def initialize size
    @pool  = {}
    @queue = Queue.new
    set_size size
  end

  ##
  # Get the current hash from the pool. Blocks if none are available.

  def checkout
    thread = Thread.current

    return thread unless @size

    @pool[thread] ||= @queue.pop
  end

  def list
    return Thread.list unless @size

    @pool.values
  end

  def release thread = Thread.current
    return unless @size

    key = @pool.key thread
    current = @pool.delete key if key
    @queue.push current        if current
  end

  def set_size size
    @size = size
    @pool.clear
    @queue.clear

    return unless @size

    @size.times do
      @queue << {}
    end
  end

end
