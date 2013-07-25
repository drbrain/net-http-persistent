require 'thread'

class Pool
  @@pool  = {}
  @@queue = Queue.new

  def self.set_size size
    @@pool.clear
    @@queue.clear

    @size = size.times do
      @@queue << {}
    end
  end
  set_size 5

  ##
  # Get the current hash from the pool. Blocks if none are available.

  def self.current
    @@pool[Thread.current] ||= @@queue.pop
  end

  def list
    @@pool.values
  end

  def self.release thread = Thread.current
    current = @@pool.delete thread
    @@queue.push current if current
  end

end
