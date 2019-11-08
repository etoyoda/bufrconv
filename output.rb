#!/usr/bin/ruby

class Output

  def initialize cfgstr = ''
    @file = nil
    @cccc = 'RJXX'
    @fmt = :ia2
    cfgstr.strip.split(/,/).each{|spec|
      case spec
      when /^FMT=(.+)/i then @fmt = $1.to_sym
      when /^FILE=(.+)/i then @file = $1
      when /^CCCC=(.+)/i then @cccc = $1
      when /^\w+=/ then $stderr.puts "unknown option #{spec}"
      else @file = spec
      end
    }
    @fp = @file ? File.open(@file, 'wb') : $stdout
    @fmt = :ia2 if @fp.tty?
    # failsafe
    @buf = []
    @ahl = nil
    @n = 0
  end

  def startmsg ttaaii, yygggg
    case @fmt
    when :ia2
      ahl = "#{ttaaii} #{@cccc} #{yygggg}"
      raise Errno::EDOM, "too many msgs in FMT=ia2" if @n > 999
      nnn = format('%03u', @n)
      @fp.puts "ZCZC #{nnn}     \r\r\n#{ahl}\r\r"
    when :bso
      @buf = []
    else raise Errno::ENOSYS, "fmt = #@fmt"
    end
    @n += 1
    ahl
  end

  def puts line
    case @fmt
    when :ia2
      @fp.puts line
    when :bso
      @buf.push line
    end
  end

  def flush
    case @fmt
    when :ia2
      @fp.puts "\n\n\n\n\n\n\n\nNNNN\r\r"
      @fp.flush
    when :bso
      @fp.write @buf.join if @buf
    end
    @buf = nil
  end

end
