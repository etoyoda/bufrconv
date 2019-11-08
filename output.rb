#!/usr/bin/ruby

class Output

  def initialize cfgstr = ''
    @file = @fmt = nil
    @cccc = 'RJXX'
    cfgstr.strip.sub(/^-o/, '').split(/,/).each{|spec|
      case spec
      when /^FMT=(.+)/i then @fmt = $1.to_sym
      when /^FILE=(.+)/i then @file = $1
      when /^CCCC=(.+)/i then @cccc = $1
      when /^\w+=/ then $stderr.puts "unknown option #{spec}"
      else @file = spec
      end
    }
    if @fmt.nil? then
      @fmt = if @file then :BSO else :IA2 end
    end
    @fp = @file ? File.open(@file, 'wb:BINARY') : $stdout
    # failsafe
    @buf = []
    @ahl = nil
    @n = 0
    @ahldict = {}
  end

  def startmsg ttaaii, yygggg
    @ahl = "#{ttaaii} #{@cccc} #{yygggg}"
    if @ahldict.include? @ahl then
      @ahl += ' RRA'
      while @ahldict.include? @ahl and / RRX$/ !~ @ahl
        @ahl = @ahl.succ
      end
    end
    @ahldict[@ahl] = true
    case @fmt
    when :IA2
      @n = 0 if @n > 999
      nnn = format('%03u', @n)
      @fp.puts "ZCZC #{nnn}     \r\r\n#{@ahl}\r\r\n"
    when :BSO
      raise Errno::EDOM, "more than 999 messages" if @n > 999
      @buf = ["\n", @ahl, "\n"]
    else raise Errno::ENOSYS, "fmt = #@fmt"
    end
    @n += 1
    @ahl
  end

  def puts line
    case @fmt
    when :IA2
      @fp.puts line
    when :BSO
      @buf.push line
    end
  end

  def print_fold words
    buf = []
    for word in words
      buflen = buf.inject(0){|len, tok| len + 1 + tok.length}
      if buflen + word.length > 64 then
        puts(buf.join(' ') + "\r\r\n")
        buf = [word]
      else
        buf.push word
      end
    end
    puts(buf.join(' ') + "\r\r\n") unless buf.empty?
  end

  def makebch
    ver = 0x35
    btype = 0x10 # for alphanumeric msg
    kind = 0x21 # domestic obs
    anlen = 0 # for alphanumeric msg
    naps = 0x20
    bchpack = "CxxxxCCxxCnC x6 C"
    bch = [ver, btype, kind, anlen, 0, naps, 0].pack(bchpack)
    sum = bch.unpack('n10').inject(:+) & 0xFFFF_FFFF
    while not (sum & 0xFFFF_0000).zero?
      sum = (sum >> 16) + (sum & 0xFFFF)
    end
    sum = 0xFFFF & ~sum
    [ver, btype, kind, anlen, sum, naps, 0].pack(bchpack)
  end

  def flush
    case @fmt
    when :IA2
      @fp.puts "\n\n\n\n\n\n\n\nNNNN\r\r\n"
      @fp.flush
    when :BSO
      @buf.unshift(makebch())
      @buf.push "\x03"
      msg = @buf.join
      @buf = nil
      @fp.write format('%08u00', msg.bytesize)
      @fp.write msg
    end
  end

end
