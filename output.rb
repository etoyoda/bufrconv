#!/usr/bin/ruby

class Output

  def initialize cfgstr = ''
    @file = nil
    @fmt = :ia2
    cfgstr.strip.split(/,/).each{|spec|
      case spec
      when /^fmt=(.+)/ then @fmt = $1.to_sym
      when /^file=(.+)/, /^\W/ then @file = $1
      when /^\w+=/ then $stderr.puts "unknown option #{spec}"
      else @file = spec
      end
    }
    @fp = @file ? File.open(@file, 'wb') : $stdout
    @fmt = :ia2 if @fp.tty?
    # failsafe
    @buf = []
  end

  def beginmsg ahl
    case @fmt
    when :ia2
    when :bso
      @buf = []
    else raise Errno::ENOSYS, "fmt = #@fmt"
    end
  end

  def puts line
    #raise "call beginmsg before puts" if @buf.nil?
    case @fmt
    when :ia2
      @fp.puts line
    when :bso
      @buf.push line
    end
  end

  def flush
    @fp.write @buf.join if @buf
    @buf = nil
  end


end
