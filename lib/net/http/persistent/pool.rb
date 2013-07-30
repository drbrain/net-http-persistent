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

    cleanup

    @pool[thread] ||= @queue.pop
  end

  def list
    return Thread.list unless @size

    @pool.values
  end

  def release worker = nil
    return unless @size

    key = @pool.key worker
    @queue.push @pool.delete key if key
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

  private

  def cleanup
    @pool.each do |thr, worker|
      release worker unless thr.alive?
    end
  end

end
