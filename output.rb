#!/usr/bin/ruby

require 'time'
require 'digest/md5'

class Output

  # @buf 配列中で AHL の代わりに置くダミー。これを入れたまま join すると
  # 例外を生じる。
  class DummyAHL
    def to_str
      raise "BUG"
    end
  end

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
    if @ofile.nil? then
      case @fmt
      when :ZIP
        @ofile = 'OUTPUT.zip'
        $stderr.puts "output to #{@ofile}"
      end
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
    @rawfp = nil
    if @ofile then
      case @fmt
      when :BSO, :IA2
	@fp = File.open(@ofile, 'wb:BINARY')
      when :ZIP
        require 'zip'
	@fp = Zip::OutputStream.open(@ofile)
      else raise Errno::ENOSYS, "fmt = #@fmt"
      end
    else
      @fp = $stdout
    end
    # 電文毎にクリアする変数
    init_vars
    # 電文通番
    @n = 0
  end

  def init_vars
    @buf = @stnlist = @ctr = @gahl = nil
    @ahl = @tt = @yygggg = @cflag = nil
    @bbox = nil
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

  def make_aa
    # 地点リストがあればそれを使おうとする
    unless @stnlist.empty?
      aalist = @stnlist.map{|idx|
	idx3 = idx.sub(/..$/, '..')
	idx4 = idx.sub(/.$/, '.')
	@table_idxaa[idx3] or @table_idxaa[idx4] or @table_idxaa[idx]
      }.compact.uniq
      return aalist.first if aalist.size == 1
      # 地点からひとつに決められない時は発信センターによる
      # 欠測遅延があるため地点は順不同となり、多数決や先着では安定しないため
      $stderr.puts "undetermined #{aalist.inspect}" if $VERBOSE
    end
    # 経緯度範囲があれば SHIP 扱い
    unless @bbox.nil?
      return 'VA' if bbox_inside(30, -60, -35,  70)
      return 'VB' if bbox_inside(90,   5,  70, 180)
      return 'VC' if bbox_inside( 5, -60,-120, -35)
      return 'VD' if bbox_inside(90,   5,-180, -35)
      return 'VE' if bbox_inside( 5, -60,  70, 240)
      return 'VF' if bbox_inside(90,  30, -35,  70)
      return 'VJ' if bbox_inside(-60,-90,-180, 180)
      return 'VX'
    end
    @table_c11[@ctr] or 'XX'
  end

  def make_ahl md5
    aa = make_aa()
    @ahl = "#{@tt}#{aa}99 #{@cccc} #{@yygggg}"
    # ヘッダの如何を問わず、既存に同一内容電文を出していたら nil を返す
    # そうすると呼び出し元 flush は出力をやめて終了する
    for ahl in @hist.keys
      if ahl == md5 then
        t, m = @hist[ahl]
        $stderr.puts "dup text=#{md5[0,7]} as #{m} on #{t}"
        return nil
      end
      t, m = @hist[ahl]
      if md5 == m then
        $stderr.puts "dup text=#{md5[0,7]} as #{ahl} on #{t}"
        return nil
      end
    end
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
    $stderr.puts "ok #{@ahl} text=#{md5[0,7]} from #{@gahl}"
    @hist[@ahl] = [@now, md5]
    @hist[md5] = [@now, @ahl]
    @ahl
  end

  def init_table_c11 dbpath
    require 'time'
    File.open(File.join(dbpath, 'table_c11'), 'r:UTF-8') {|fp|
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

  def startmsg tt, yygggg, msg
    @tt, @yygggg = tt, yygggg
    @ctr = msg[:ctr] || 255
    @cflag = msg[:cflag]
    @gahl = msg.ahl
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
      @buf = ["ZCZC #{nnn}     \r\r\n", DummyAHL.new, "\r\r\n"]
    when :BSO
      # BSO: NAPS→アデスで用いる国内バッチFTP形式。
      raise Errno::EDOM, "more than 999 messages" if @n > 999
      @buf = ["\n", DummyAHL.new, "\n"]
    when :ZIP
      @buf = ["", DummyAHL.new, "\r\r\n"]
    end
    @stnlist = []
    @n += 1
    nil
  end

  def tell_latlon lat, lon
    unless @bbox
      @bbox = {:n=>-90.0, :s=>90.0,
        :w=>180.0, :e=>-180.0,
	:W=>360.0, :E=>0.0}
    end
    @bbox[:n] = [@bbox[:n], lat].max
    @bbox[:s] = [@bbox[:s], lat].min
    @bbox[:w] = [@bbox[:w], lon].min
    @bbox[:e] = [@bbox[:e], lon].max
    elon = (lon < 0) ? (lon + 360) : lon
    @bbox[:W] = [@bbox[:W], elon].min
    @bbox[:E] = [@bbox[:E], elon].max
    self
  end

  def bbox_inside n, s, w, e
    return nil unless @bbox
    return false if @bbox[:n] > n
    return false if @bbox[:s] < s
    (@bbox[:w] >= w && @bbox[:e] <= e) || (@bbox[:W] >= w && @bbox[:E] <= e)
  end

  def tell_station idx
    @stnlist.push idx
    self
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
    raise "BUG" unless DummyAHL === @buf[1]
    @buf[1] = make_ahl(md5)
    if @buf[1].nil? then
      return
    end
    case @fmt
    when :IA2
      @buf.push "\n\n\n\n\n\n\n\nNNNN\r\r\n"
      msg = @buf.join
      @fp.write msg
      @fp.flush
    when :BSO
      @buf.unshift(makebch())
      @buf.push "\x03"
      msg = @buf.join
      @fp.write format('%08u00', msg.bytesize)
      @fp.write msg
      @fp.flush
    when :ZIP
      fnam = @buf[1].gsub(/\W/, '_') + '.txt'
      @fp.put_next_entry(fnam)
      @fp.write @buf.join
    end
  ensure
    init_vars
  end

  def close
    save_hist
    @fp.close
  end

end
