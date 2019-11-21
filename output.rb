#!/usr/bin/ruby

require 'time'
require 'digest/md5'

class Output

  def initialize cfgstr = '', dbpath = '.'
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
    @table_c11 = {}
    init_table_c11(dbpath)
    @table_idxaa = {}
    init_table_idxaa(dbpath)
    @fp = @ofile ? File.open(@ofile, 'wb:BINARY') : $stdout
    @buf = []
    @stnlist = []
    @ahl = @cflag = nil
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
    exit 16
  end

  def make_ahl md5
    # ヘッダの如何を問わず、既存に同一内容電文を出していたら nil を返す
    # そうすると呼び出し元 flush は出力をやめて終了する
    for ahl in @hist.keys
      if ahl == md5 then
        t, m = @hist[ahl]
        $stderr.puts "dup #{m} on #{t}"
        return nil
      end
      t, m = @hist[ahl]
      if md5 == m then
        $stderr.puts "dup #{ahl} on #{t}"
        return nil
      end
    end
    # 南極ヘッダ修正
    @ahl.sub!(/^(..)../, "\\1AA") if @stnlist.any?{|idx| /^89/ === idx}
    # BBB 付与
    if @hist['RRYMODE'] then
      # 履歴ファイルの読み込みに失敗した場合
      @hist[@ahl] = [@now, 'RRYMODE']
      @ahl += (@cflag ? ' CCY' : ' RRY')
    elsif @hist.include? @ahl then
      if @hist[@ahl][1] == 'RRYMODE' then
        @ahl += (@cflag ? ' CCY' : ' RRY')
      else
        @ahl += (@cflag ? ' CCA' : ' RRA')
        while @hist.include? @ahl and /[A-W]$/ =~ @ahl
          @ahl = @ahl.succ
        end
      end
    elsif @cflag then
      @ahl += ' CCA'
      while @hist.include? @ahl and /[A-W]$/ =~ @ahl
        @ahl = @ahl.succ
      end
    end
    $stderr.puts "ok #{@ahl} text=#{md5}"
    @hist[@ahl] = [@now, md5]
    @hist[md5] = [@now, @ahl]
    @ahl
  end

  def init_table_c11 dbpath
    require 'time'
    File.open(File.join(dbpath, 'table_c11'), 'r') {|fp|
      fp.each_line{|line|
      begin
        next if /^\s*#/ === line
        line.chomp!
        tfilter, ctr, aa, desc = line.split(/\t/, 4)
        raise ArgumentError, "bad aa=#{aa}" unless /^[A-Z][A-Z]$/ === aa
        stime, etime = tfilter.split(/\//, 2)
        next if Time.parse(stime) > @now
        next if Time.parse(etime) < @now
        @table_c11[ctr.to_i] = aa
      rescue ArgumentError => e
        $stderr.puts ['table_c11:', fp.lineno, ': ', e.message].join
      end
      }
    }
  end

  def init_table_idxaa dbpath
    require 'time'
    File.open(File.join(dbpath, 'table_station'), 'r') {|fp|
      fp.each_line{|line|
        next if /^\s*#/ === line
        line.chomp!
        idx, aa, dummy = line.split(/\t/)
        @table_idxaa[idx] = aa
      }
    }
  end

  def make_aa hdr
    @table_c11[hdr[:ctr]] or 'XX'
  end

  def startmsg tt, yygggg, hdr
    ttaaii = [tt, make_aa(hdr), '99'].join
    @ahl = "#{ttaaii} #{@cccc} #{yygggg}"
    @cflag = hdr[:cflag]
    #
    # 新形式を追加する場合、 @buf は 3 要素、 @ahl は 2 つめになるようにする
    # （flush で個数・位置決め打ちで処理しているから）
    #
    case @fmt
    when :IA2
      # IA2: GTS マニュアルに定める IA2 文字セット回線での電文形式。
      # すべての文字が printable なのでデバッグ用にも使っている。
      @n = 0 if @n > 999
      nnn = format('%03u', @n)
      @buf = ["ZCZC #{nnn}     \r\r\n", @ahl, "\r\r\n"]
    when :BSO
      # BSO: NAPS→アデスで用いる国内バッチFTP形式。
      raise Errno::EDOM, "more than 999 messages" if @n > 999
      @buf = ["\n", @ahl, "\n"]
    else raise Errno::ENOSYS, "fmt = #@fmt"
    end
    @stnlist = []
    @n += 1
    @ahl
  end

  def station idx
    @stnlist.push idx
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
    # MD5 を計算する対象は、AHL の次の行からエンド行を除く本文。
    # 先頭に CR CR LF を加えたものが GTS マニュアルでいう text になる。
    # BSO 形式ではそれが LF なので、混乱を避けるため計算から除外している。
    md5 = Digest::MD5.hexdigest(@buf[3..-1].join)
    @buf[1] = make_ahl(md5)
    if @buf[1].nil? then
      return
    end
    case @fmt
    when :IA2
      @buf.push "\n\n\n\n\n\n\n\nNNNN\r\r\n"
      msg = @buf.join
    when :BSO
      @buf.unshift(makebch())
      @buf.push "\x03"
      msg = @buf.join
      @fp.write format('%08u00', msg.bytesize)
    end
    @fp.write msg
    @fp.flush
  ensure
    @stnlist = @buf = @cflag = nil
  end

  def close
    save_hist
  end

end
