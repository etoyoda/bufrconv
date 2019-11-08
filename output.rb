#!/usr/bin/ruby

class Output

  def initialize opts = {}
    @file = opts[:file]
    @fp = @file ? File.open(@file, 'wb') : $stdout
    @fmt = (opts[:fmt] || :ia2).to_sym
    if @fp.tty? and :ia2 != @fmt then
      @fmt = :ia2
    end
    @buf = nil
  end

  def beginmsg ahl
    case @fmt
    when :ia2
      @buf = :unused
    when :bso
      @buf = []
    else raise Errno::ENOSYS, "fmt = #@fmt"
    end
  end

  def puts line
    raise "call beginmsg before puts" if @buf.nil?
    case @fmt
    when :ia2
      @fp.puts line
    when :bso
      @buf.push line
    end
  end

  def flush
    @fp.flush if :ia2 === @fmt
  end

  def endmsg
    @fp.write @buf.join if @buf
    flush
    @buf = nil
  end


end
