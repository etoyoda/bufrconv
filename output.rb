#!/usr/bin/ruby

require 'time'

class Output

  def initialize cfgstr = ''
    @now = Time.now.utc
    # 動作オプションの設定
    @ofile = @fmt = @histin = @histout = nil
    # デフォルトの発信官署４字略号
    @cccc = 'RJXX'
    # 注意：保存期間を27日以上に設定してはならない。3月に事故を起こす。
    @keep = 20
    cfgstr.strip.sub(/^-o/, '').split(/,/).each{|spec|
      case spec
      when /^FMT=(.+)/i then @fmt = $1.to_sym
      when /^FILE=(.+)/i then @ofile = $1
      when /^HIN=(.+)/i then @histin = $1
      when /^HOUT=(.+)/i then @histout = $1
      when /^KEEP=(\d+)/i then @keep = $1.to_i
      when /^CCCC=(.+)/i then @cccc = $1
      when /^\w+=/ then $stderr.puts "unknown option #{spec}"
      else @ofile = spec
      end
    }
    # いくつかのオプションは省略時に暗黙設定
    if @fmt.nil? then
      @fmt = if @ofile then :BSO else :IA2 end
    end
    if @histout and @histin.nil? then
      @histin = @histout
    end
    # 内部変数
    @hist = {}
    init_hist
    @fp = @ofile ? File.open(@ofile, 'wb:BINARY') : $stdout
    @buf = []
    @ahl = nil
    @n = 0
  end

  def init_hist
    return unless @histin
    expire = @now - 86400 * @keep
    File.open(@histin, 'r'){|ifp|
      ifp.each_line{|line|
        ahl, stime, fingerprint = line.chomp.split(/\t/)
        time = Time.parse(stime)
	next if time < expire
	@hist[ahl] = [time, fingerprint]
      }
    }
  rescue StandardError => e
    $stderr.puts("init_hist: #{e.message}; RRY/CCY mode")
    @hist['RRYMODE'] = [@now, '-']
  end

  def save_hist
    return unless @histout
    File.open(@histout, 'w'){|ofp|
      @hist.each{|ahl, vals|
        next if 'RRYMODE' == ahl
        time, fingerprint = vals
        stime = time.utc.strftime('%Y-%m-%dT%H:%M:%S.%L')
        ofp.puts [ahl, stime, fingerprint].join("\t")
      }
    }
  rescue StandardError => e
    $stderr.puts("save_hist: " + e.message)
  end

  def make_ahl ttaaii, yygggg, cflag
    @ahl = "#{ttaaii} #{@cccc} #{yygggg}"
    # 履歴ファイルの読み込みに失敗した場合
    if @hist['RRYMODE'] then
      @hist[@ahl] = [@now, 'RRYMODE']
      @ahl += (cflag ? ' CCY' : ' RRY')
      @hist[@ahl] = [@now, '-']
      return @ahl
    end
    if @hist.include? @ahl then
      if @hist[@ahl][1] == 'RRYMODE' then
	@ahl += (cflag ? ' CCY' : ' RRY')
      else
	@ahl += (cflag ? ' CCA' : ' RRA')
	while @hist.include? @ahl and /[A-W]$/ =~ @ahl
	  @ahl = @ahl.succ
	end
      end
    end
    @hist[@ahl] = [@now, '-']
    return @ahl
  end

  def startmsg ttaaii, yygggg, cflag
    make_ahl(ttaaii, yygggg, cflag)
    case @fmt
    when :IA2
      @n = 0 if @n > 999
      nnn = format('%03u', @n)
      @buf = ["ZCZC #{nnn}     \r\r\n", @ahl, "\r\r\n"]
    when :BSO
      raise Errno::EDOM, "more than 999 messages" if @n > 999
      @buf = ["\n", @ahl, "\n"]
    else raise Errno::ENOSYS, "fmt = #@fmt"
    end
    @n += 1
    @ahl
  end

  def puts line
    @buf.push line
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
      @buf.push "\n\n\n\n\n\n\n\nNNNN\r\r\n"
      @fp.write @buf.join
      @fp.flush
    when :BSO
      @buf.unshift(makebch())
      @buf.push "\x03"
      msg = @buf.join
      @buf = nil
      @fp.write format('%08u00', msg.bytesize)
      @fp.write msg
      @fp.flush
    end
    save_hist
  end

end
