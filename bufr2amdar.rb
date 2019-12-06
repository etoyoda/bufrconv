#!/usr/bin/ruby

$LOAD_PATH.push File.dirname($0) ##del
require 'bufrdump' ##del
require 'output' ##del

class Bufr2amdar

  def initialize out
    @out = out
    @hdr = @reftime = nil
    @ahl_is_set = nil
  end

  def newbufr hdr
    @hdr = hdr
    rt = @hdr[:reftime]
    @reftime = Time.gm(rt.year, rt.mon, rt.day, rt.hour)
    gg = (rt.hour + 2) / 3 * 3
    @reftime += (3600 * (gg - rt.hour))
    @ahl_is_set = false
  end

  # 出力ハンドラにヘッダを設定する。既にしていたらやらない。
  def startmsg codename, yygg
    return if @ahl_is_set
    tt = 'UD' # Part A
    yygggg = @reftime.strftime('%d%H00')
    @out.startmsg(tt, yygggg, @hdr)
    @out.print_fold([codename, yygg])
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

  # 記述子 fxy を含む最初の記述子の *直前* の記述子-値ペアを返す
  def find_prev tree, fxy
    tree.size.times {|i|
      if tree[i].first == fxy then
        return tree[i-1][1]
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

  def subset tree
    report = []

    #--- Section 1 ---
    # AMDAR YYGG
    yy = find(tree, '004003') || @reftime.day
    _GG = find(tree, '004004') || @reftime.hour
    yygg = [itoa2(yy), itoa2(_GG)].join

    startmsg('AMDAR', yygg)

    #--- Section 2 ---
    # ipipip
    ip3 = case find(tree, '008009')
      when 0..2 then 'UNS'
      when 3 then 'LVR'
      when 4 then 'LVW'
      when 5, 7..10 then 'ASC'
      when 6, 11..14 then 'DSC'
      else '///'
      end
    report.push ip3

    # IA...IA
    _IA = find(tree, '001008').to_s.strip
    _IA = 'AMDAR' if _IA.empty?
    report.push _IA

    # LaLaLaLaA LoLoLoLoLoB

    lat = find(tree, '005001')
    lon = find(tree, '006001')
    @out.tell_latlon(lat, lon)

    latmin = (lat.abs * 60 + 0.5).floor
    la12 = latmin / 60
    la34 = latmin % 60
    latsign = (lat >= 0.0) ? 'N' : 'S'
    report.push [itoa2(la12), itoa2(la34), latsign].join

    lonmin = (lon.abs * 60 + 0.5).floor
    lo123 = lonmin / 60
    lo45 = lonmin % 60
    lonsign = (lon >= 0.0) ? 'E' : 'W'
    report.push [itoa3(lo123), itoa2(lo45), lonsign].join

    gg = find(tree, '004005')
    report.push [yygg, itoa2(gg)].join

    # ShhIhIhI
    pheight = find(tree, '007010')
    if pheight.nil? then
      pheight = find(tree, '007002')
    end
    if pheight then
      pheight *= 3.280839895
      sh = (pheight >= 0) ? 'F' : 'A'
      hihihi = (pheight + 50) / 100
      report.push [sh, itoa3(hihihi)].join
    end

    # SSTATATA
    t = find(tree, '012101')
    if t.nil? then
      t = find(tree, '012001')
    end
    if t
      t -= 273.15
      ss = (t >= 0) ? 'PS' : 'MS'
      t = (t.abs * 10 + 0.5).floor
      report.push [ss, itoa3(t)].join
    else
      report.push 'PS///'
    end

    td = find(tree, '012103')
    if td
      td -= 273.15
      sd = (td >= 0) ? 'PS' : 'MS'
      td = (td.abs * 10 + 0.5).floor
      report.push [sd, itoa3(td)].join
    end

    ddd = find(tree, '011001')
    fff = find(tree, '011002')
    fff = (fff * 1.9438445 + 0.5).floor if fff
    report.push [itoa3(ddd), '/', itoa3(fff)].join if ddd or fff

    tb = case find(tree, '011037')
      when 0..1 then 0
      when 2..9 then 1
      when 10..20 then 2
      when 21..27 then 3
      else nil
      end
    report.push ['TB', itoa1(tb)].join

    tqc = case find_prev(tree, '012101')
      when 0 then 0
      when 1 then 1
      else nil
      end
    report.push ['S//', itoa1(tqc)].join if tqc

    report.last.sub!(/$/, '=')
    @out.print_fold(report)
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
  encoder = Bufr2amdar.new(Output.new(outopts, db.path))
  ARGV.each{|fnam|
    BUFRScan.filescan(fnam){|bufrmsg|
      next unless bufrmsg[:cat] == 4
      case bufrmsg[:subcat]
      when 0
      else next
      end
      db.decode(bufrmsg, :direct, encoder)
    }
  }
  encoder.close
end
