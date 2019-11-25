#!/usr/bin/ruby

$LOAD_PATH.push File.dirname($0) ##del
require 'bufrdump' ##del
require 'output' ##del

class Bufr2temp

  class EDOM < Errno::EDOM
  end

  def initialize out
    @out = out
    @hdr = @reftime = nil
    @ahl_is_set = nil
    @knot = nil
  end

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
    tt = 'US' # Part A
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

  def levsort levbranch
    levdb = {}
    levbranch.each{|levset|
      flags = find(levset, '008042')
      pres = find(levset, '007004')
      if pres then
	pres = (pres / 100).to_i
      else
        height = find(levset, '007009')
	pres = rough_pressure(height)
	levdb[:APPROX] = true
      end
      levdb[pres] = levset if 0 != (flags & 0x10000)
      levdb[:MAXW] = levset if 0 != (flags & 0x04000)
    }
    return levdb
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
    raise EDOM, "no standard level reported" if groups.empty?
    return groups
  end

  def ddfff levset
    dd = find(levset, '011001')
    fff = find(levset, '011002')
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
    indic = levdb[:APPROX] ? '55' : '44'
    report.push [indic, itoa1(grp[:n]), grp[:pp]].join
    grp[:pres].each{|pres|
      levset = levdb[pres]
      report.push ddfff(levset)
    }
  end

  def encode_maxw report, levset
    ppp = find(levset, '007004')
    if ppp then
      ppp *= 10 if ppp < 100_00
      ppp = (ppp / 100) % 1000
      report.push ['77', itoa3(ppp)].join
    else
      hhhh = find(levset, '007009')
      hhhh = ((hhhh + 5) / 10).to_i % 10000 if hhhh
      report.push ['7',  itoa4(hhhh)].join
    end

    report.push ddfff(levset)
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

    levbranch = branch(tree, 0)
    levdb = levsort(levbranch)
    groups = scanlevs(levdb)

    # YYGGId
    yy = find(tree, '004003') || @reftime.day
    yy += 50 if @knot
    _GG1 = find(tree, '004004') || @reftime.hour
    a4 = encode_a4(find(tree, '002003'))
    a4 = 0 if a4.nil? and not levdb[:APPROX]
    report.push [itoa2(yy), itoa2(_GG1), itoa1(a4)].join

    # IIiii
    _II = find(tree, '001001')
    iii = find(tree, '001002')
    stnid = [itoa2(_II), itoa3(iii)].join
    report.push stnid

    set_ahl
    @out.station stnid

    groups.each{|grp|
      encode_grp(grp, levdb, report)
    }

    if levdb[:MAXW] then
      encode_maxw(report, levdb[:MAXW])
    else
      report.push '77999'
    end

    report.last.sub!(/$/, '=')
    @out.print_fold(report)
  rescue EDOM => e
    $stderr.puts e.message + @hdr[:meta].inspect
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
