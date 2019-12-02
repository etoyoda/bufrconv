#!/usr/bin/ruby

$LOAD_PATH.push File.dirname($0) ##del
require 'bufrdump' ##del
require 'output' ##del

class Bufr2temp

  class ENOMSG < Errno::ENOMSG
  end

  def initialize out
    @out = out
    @hdr = @reftime = nil
    @ahl_is_set = nil
    @knot = nil
    @verbose = false
  end

  attr_accessor :verbose

  def newbufr hdr
    @hdr = hdr
    rt = @hdr[:reftime]
    @reftime = Time.gm(rt.year, rt.mon, rt.day, rt.hour)
    gg = (rt.hour + 2) / 3 * 3
    @reftime += (3600 * (gg - rt.hour))
    case @hdr[:ctr]
    when 34 then
      @knot = true
    end
    @ahl_is_set = false
  end

  # 出力ハンドラにヘッダを設定する。既にしていたらやらない。
  def set_ahl
    return if @ahl_is_set
    tt = 'UP' # Part A
    yygggg = @reftime.strftime('%d%H00')
    @out.startmsg(tt, yygggg, @hdr)
    @ahl_is_set = true
  end

  # 記述子 fxy を含む最初の記述子-値ペアを返す
  def find tree, fxy
    for elem in tree
      if elem.first == fxy then
        return elem[1]
      elsif Array === elem.first
        r = find(elem.first, fxy)
        return r if r
      end
    end
    return nil
  end

  # 記述子 fxy を含む n 個目の記述子-値ペアを返す (n >= 1)
  # ただし反復の中には入らない
  def find_nth tree, fxy, nth = 2
    for elem in tree
      if elem.first == fxy then
        nth -= 1
        return elem[1] if nth.zero?
      end
    end
    return nil
  end

  # n個目の反復を探す (n >= 0)
  def branch tree, nth = 0
    return nil if tree.nil?
    tree.size.times{|i|
      elem = tree[i]
      case elem.first
      when /^1/
        if nth <= 0 then
          i += 1 if /^031/ === tree[i+1].first
          return tree[i + 1]
        end
        nth -= 1
      end
    }
    return nil
  end

  def itoa1 ival
    case ival when 0..9 then format('%01u', ival) else '/' end
  end

  def itoa2 ival
    case ival when 0..99 then format('%02u', ival) else '//' end
  end

  def itoa3 ival
    case ival when 0..999 then format('%03u', ival) else '///' end
  end

  def itoa4 ival
    case ival when 0..9999 then format('%04u', ival) else '////' end
  end

  def rough_pressure h
    case h
    when 1350..1650 then 850
    when 2790..3410 then 700
    when 5220..6380 then 500
    when 6840..8360 then 400
    when 8550...10030 then 300
    when 10030...11400 then 250
    when 11400...13200 then 200
    when 13200...15300 then 150
    when 15300...17500 then 100
    when 17500...19500 then 70
    when 19500...22200 then 50
    when 22200...25200 then 30
    when 25200...28600 then 20
    when 28600...33000 then 10
    else nil
    end
  end

  PMAP = [[850, 1500], [700, 3000], [500, 5500], [400, 7000], [300, 9000],
    [250, 10500], [200, 12000], [150, 13500], [100, 16000]]

  def p_and_diff h
    for pp, hh in PMAP
      diff = (hh - h).abs
      return [pp, diff] if diff < 500
    end
    return nil
  end

  def levsort tree
    levdb = {}
    levbranch = branch(tree, 0)
    #
    # WMO標準テンプレート、008042フラグ、007004気圧または007009高度がある
    #
    levbranch.each{|levset|
      flags = find(levset, '008042')
      next if flags.nil?
      pres = find(levset, '007004')
      if pres then
	pres = (pres / 100).to_i
	apres = format('p%02u', pres / 10)
	levdb[apres] = true
      else
        height = find(levset, '007009')
	pres = rough_pressure(height)
      end
      # bit 2 of 18 - Standard level
      if 0 != (flags & 0x10000) then
	levdb[pres] = levset
      end
      # bit 4 of 18 - Maximum wind level
      if 0 != (flags & 0x04000) then
	levdb[:MAXW] = levset
	# bit 14 of 18 - Top of wind sounding
	levdb[:MAXWENDS] = true if 0 != (flags & 0x00010)
      end
    }
    return levdb unless levdb.empty?
    #
    # 欧州型プロファイラ、007007高度が入る
    #
    levbranch.each{|levset|
      hgt = find(levset, '007007')
      dd = find(levset, '011001')
      next if hgt.nil? or dd.nil?
      pres, diff = p_and_diff(hgt)
      next if pres.nil?
      dpres = format('d%03u', pres)
      xdiff = levdb[dpres] || 9999
      next if diff > xdiff
      levdb[pres] = levset
      levdb[dpres] = diff
    }
    $stderr.puts levdb.inspect if @verbose and not levdb.empty?
    return levdb unless levdb.empty?
    #
    # 豪州型プロファイラ
    #
    stnlev = find(tree, '007001')
    if stnlev then
      # 日本型プロファイラも（やっつけだが）捨てない
      subbranch = branch(levbranch.last, 0)
      levbranch = subbranch if subbranch
      #
      levbranch.each{|levset|
        h = find(levset, '007006')
	next if h.nil?
	next if find(levset, '011001').nil? and find(levset, '011003').nil?
	hgt = stnlev + h
	pres, diff = p_and_diff(hgt)
	next if pres.nil?
	dpres = format('d%03u', pres)
	xdiff = levdb[dpres] || 9999
	next if diff > xdiff
	levdb[pres] = levset
	levdb[dpres] = diff
      }
    end

    return levdb
  ensure
    $stderr.puts levdb.inspect if @verbose 
  end

  STDLEVS = [
    [850, '85', '8'],
    [700, '70', '7'],
    [500, '50', '5'],
    [400, '40', '4'],
    [300, '30', '3'],
    [250, '25', '2'],
    [200, '20', '2'],
    [150, '15', '1'],
    [100, '10', '1']
  ]

  def scanlevs levdb
    groups = []
    i = 0
    while STDLEVS[i]
      pres, pp, pid = STDLEVS[i]
      unless levdb.include?(pres) then
        i += 1
        next
      end
      if lev2 = STDLEVS[i + 2] and levdb.include?(lev2.first) then
        n = 3
	pres = [pres, STDLEVS[i+1][0], lev2.first]
      elsif lev1 = STDLEVS[i + 1] and levdb.include?(lev1.first) then
        n = 2
	pres = [pres, lev1.first]
      else
        n = 1
	pres = [pres]
      end
      grp = {:pp => pp, :n => n, :pres => pres}
      groups.push grp
      i += 3
    end
    raise ENOMSG, "No std level" if groups.empty?
    return groups
  end

  def ddfff levset
    return '/////' unless levset
    dd = find(levset, '011001')
    fff = find(levset, '011002')
    unless dd then
      u = find(levset, '011003')
      v = find(levset, '011004')
      if u and v then
	fff = Math.hypot(u, v)
	dd = Math.atan2(u, v) / Math::PI * 180 + 180
      end
    end
    fff *= 1.9438 if fff and @knot
    dd = ((dd + 2.5) / 5).to_i * 5 if dd
    fff = (fff + 0.5).to_i if fff
    if dd and 0 != (dd % 10) then
      fff += 500 if fff
    end
    dd /= 10 if dd
    if dd == 21 and fff == 212 then
      $stderr.puts "21211 for dd=21 and fff=212 to avoid 21212"
      fff = 211
    end
    [itoa2(dd), itoa3(fff)].join
  end

  def encode_grp grp, levdb, report
    # 44nP1P1 .. pressure known
    # 55nP1P1 .. approximated std levs by height
    indic = levdb['p' + grp[:pp]] ? '44' : '55'
    report.push [indic, itoa1(grp[:n]), grp[:pp]].join
    grp[:pres].each{|pres|
      levset = levdb[pres]
      report.push ddfff(levset)
    }
  end

  def encode_maxw report, levset, maxwends
    return nil unless levset
    ppp = find(levset, '007004')
    if ppp then
      ppp *= 10 if ppp < 100_00
      ppp = (ppp / 100) % 1000
      indic = maxwends ? '66' : '77'
      report.push [indic, itoa3(ppp)].join
    else
      hhhh = find(levset, '007009')
      hhhh = ((hhhh + 5) / 10).to_i % 10000 if hhhh
      return false unless hhhh
      indic = maxwends ? '6' : '7'
      report.push [indic,  itoa4(hhhh)].join
    end
    report.push ddfff(levset)
    true
  end

  def encode_a4 e002003
    case e002003
    when 0..3 then e002003
    when 4 then 5 # VLF-Omega
    when 5 then 6 # Loran-C
    when 6 then 7 # Wind profiler (generic)
    when 7 then 8 # Satellite navigation
    when 8 then 7 # RASS
    when 9 then 7 # Sodar
    when 10 then 7 # Lidar
    when 14 then 4 # Pressure element equiped but failed
    else nil
    end
  end

  def subset tree
    report = []

    # MiMiMjMj
    report.push "PPAA "

    levdb = levsort(tree)
    groups = scanlevs(levdb)

    # YYGGId
    yy = find(tree, '004003') || @reftime.day
    yy += 50 if @knot
    _GG1 = find(tree, '004004') || @reftime.hour
    a4 = encode_a4(find(tree, '002003'))
    a4 = 0 if a4.nil? and levdb['p85']
    report.push [itoa2(yy), itoa2(_GG1), itoa1(a4)].join

    # IIiii
    _II = find(tree, '001001')
    iii = find(tree, '001002')
    stnid = [itoa2(_II), itoa3(iii)].join
    report.push stnid

    set_ahl
    @out.tell_station stnid

    groups.each{|grp|
      encode_grp(grp, levdb, report)
    }

    unless encode_maxw(report, levdb[:MAXW], levdb[:MAXWENDS])
      report.push '77999'
    end

    report.last.sub!(/$/, '=')
    @out.print_fold(report)
  rescue ENOMSG => e
    $stderr.puts [e.message.sub(/.* - /, ''), given_ahl()].join(' ')
  end

  def given_ahl
    (@hdr[:meta] ? @hdr[:meta][:ahl] : nil) or '(ahl missing)'
  end

  def endbufr
    return unless @ahl_is_set
    @out.flush
    @hdr = @reftime = nil
    @ahl_is_set = nil
  end

  def close
    @out.close
  end

end

if $0 == __FILE__
  db = BufrDB.new(ENV['BUFRDUMPDIR'] || File.dirname($0))
  # コマンドラインオプションは最初の引数だけ
  outopts = if /^-o/ =~ ARGV.first then ARGV.shift else '' end
  encoder = Bufr2temp.new(Output.new(outopts, db.path))
  ARGV.each{|fnam|
    case fnam
    when '-v' then encoder.verbose = true; next
    when '-q' then encoder.verbose = false; next
    end
    BUFRScan.filescan(fnam){|bufrmsg|
      bufrmsg.decode_primary
      next unless bufrmsg[:cat] == 2
      case bufrmsg[:subcat]
      when 1..3, 10
      else next
      end
      db.decode(bufrmsg, :direct, encoder)
    }
  }
  encoder.close
end
