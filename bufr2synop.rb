#!/usr/bin/ruby

$LOAD_PATH.push File.dirname($0)
require 'bufrdump'

class Bufr2synop

  def initialize
    @hdr = @reftime = nil
    @ahl_hour = @knot = nil
    @out = $stdout
  end

  AA = { 28=>'IN', 34=>'JP', 36=>'TH', 37=>'MO', 38=>'CI', 40=>'KR', 67=>'AU',
    110=>'HK', 116=>'KP' }

  def newbufr hdr
    @hdr = hdr
    rt = @hdr[:reftime]
    @reftime = Time.gm(rt.year, rt.mon, rt.day, rt.hour)
    @reftime += 3600 if rt.min > 0
    @ahl_hour = @knot = false
  end

  def print_ahl
    # data category 0: Surface data - land
    return if @hdr[:cat] != 0
    return if @ahl_hour
    tt = case @reftime.hour
      when 0, 12 then 'SM'
      when 6, 18 then 'SI'
      else 'SN'
      end
    aa = AA[@hdr[:ctr]] || 'XX'
    @knot = true if 'JP' == aa
    cccc = 'RJXX'
    yygg = @reftime.strftime('%d%H')
    @out.puts "ZCZC"
    @out.puts "#{tt}#{aa}99 #{cccc} #{yygg}00"
    @out.puts "AAXX #{yygg}#{@knot ? '4' : '1'}"
    @ahl_hour = @reftime.hour
  end

  # returns the first element
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

  # caution -- this does not go recursive
  def find_nth tree, fxy, nth = 2
    for elem in tree
      if elem.first == fxy then
        nth -= 1
        return elem[1] if nth.zero?
      end
    end
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
    print_ahl
    report = []

    # IIiii
    _II = find(tree, '001001')
    iii = find(tree, '001002')
    report.push [itoa2(_II), itoa3(iii)].join

    # iRixhVV
    iR = '4'
    weather = find(tree, '020003')
    case weather
    when 4..99 then 
      ix, ww = '1', weather
    when 0, 508 then
      ix, ww = '2', nil
    when 100..199 then
      ix, ww = '7', weather - 100
    else
      ix, ww = '3', nil
    end
    h = case find(tree, '020013')
      when 0...50 then 0
      when 50...100 then 1
      when 100...200 then 2
      when 200...300 then 3
      when 300...600 then 4
      when 600...1000 then 5
      when 1000...1500 then 6
      when 1500...2000 then 7
      when 2000...2500 then 8
      when 2500 ... 9999 then 9
      else nil
      end
    vis = find(tree, '020001')
    _VV = case vis
      when 0..5000 then ((vis + 50) / 100).to_i
      when 5000..30_000 then ((vis + 50500) / 1000).to_i
      when 30_000..70_000 then ((vis - 30_000) / 5000).to_i + 80
      when 70_000..999_000 then 89
      else nil
      end
    report.push [iR, ix, itoa1(h), itoa2(_VV)].join

    # Nddff
    _N = find(tree, '020010')
    _N = ((_N + 6) / 12.5).to_i if _N
    dd = find(tree, '011001')
    dd = (dd + 5) / 10 if dd
    ff = find(tree, '011002')
    ff *= 1.9438 if ff and @knot
    case ff
    when 0 ... 99.5
      ff = (ff + 0.5).to_i
      fff = nil
    when 99.5 ... 999
      fff = ff.to_i
      ff = 99
    end
    report.push [itoa1(_N), itoa2(dd), itoa2(ff)].join
    report.push ['00', itoa3(fff)] if fff

    # 1sTTT
    _TTT = find(tree, '012101')
    case _TTT
    when 173.25 ... 273.15
      s, _TTT = '1', ((273.2 - _TTT) * 10).to_i
    when 273.15 ... 373.05
      s, _TTT = '0', ((_TTT - 273.1) * 10).to_i
    else
      s, _TTT = '/', nil
    end
    report.push ['1', s, itoa3(_TTT)].join if _TTT

    # 2snTdTdTd
    _TdTdTd = find(tree, '012103')
    case _TdTdTd
    when 173.25 ... 273.15
      sn, _TdTdTd = '1', ((273.2 - _TdTdTd) * 10).to_i
    when 273.15 ... 373.05
      sn, _TdTdTd = '0', ((_TdTdTd - 273.1) * 10).to_i
    else
      sn, _TdTdTd = '/', nil
    end
    report.push ['2', sn, itoa3(_TdTdTd)].join if _TdTdTd

    # 3P0P0P0P0
    _P0P0P0P0 = find(tree, '010004')
    _P0P0P0P0 = ((_P0P0P0P0 + 5) / 10) % 1000_0 if _P0P0P0P0 
    report.push ['3', itoa4(_P0P0P0P0)].join if _P0P0P0P0 

    # 4PPPP
    _PPPP = find(tree, '010051')
    _PPPP = ((_PPPP + 5) / 10) % 1000_0 if _PPPP 
    case _PPPP
    when 1000...9000
      a3 = find(tree, '007004')
      a3 = case a3
        when 1000_0 then '1'
        when 925_0 then '2'
        when 850_0 then '8'
        when 700_0 then '7'
        when 500_0 then '5'
        else nil
        end
      hhh = find(tree, '010009')
      hhh = hhh % 1000 if hhh
      report.push ['4', a3, itoa3(hhh)].join if a3
    else
      report.push ['4', itoa4(_PPPP)].join if _PPPP 
    end

    # 5appp

    # 6RRRtR

    # 7wwW1W2
    w1 = find(tree, '020004')
    w2 = find(tree, '020005')
    w1 = case w1
      when 3..9 then w1
      when 11..19 then w1 - 10
      else nil
      end
    w2 = case w2
      when 3..9 then w2
      when 11..19 then w2 - 10
      else nil
      end
    report.push ['7', itoa2(ww), itoa1(w1), itoa1(w2)].join if ww

    # 8NhCLCMCH
    # only the first instance of 020011 represents Nh. the rest in replication are Ns.
    _Nh = find(tree, '020011')
    _Nh = ((_Nh + 6) / 12.5).to_i if _Nh
    _CL = find(tree, '020012')
    _CL = case _CL when 30..39 then _CL - 30 else nil end
    _CM = find_nth(tree, '020012', 2)
    _CM = case _CM when 20..29 then _CM - 20 else nil end
    _CH = find_nth(tree, '020012', 3)
    _CH = case _CH when 10..19 then _CH - 10 else nil end
    report.push ['8', itoa1(_Nh), itoa1(_CL), itoa1(_CM), itoa1(_CH)].join if _Nh or _CL

    # 9GGgg
    _GG = find(tree, '004004')
    gg = find(tree, '004005')
    if _GG and _GG != @ahl_hour
      report.push ['9', itoa2(_GG), itoa2(gg)].join
    end

    @out.puts report.join(' ')
  end

  def endbufr
    return unless @ahl_hour
    @out.puts "NNNN"
    @hdr = @reftime = nil
    @ahl_hour = false
  end

end

if $0 == __FILE__
  db = BufrDB.new(ENV['BUFRDUMPDIR'] || File.dirname($0))
  pseudo_io = Bufr2synop.new
  ARGV.each{|fnam|
    BUFRScan.filescan(fnam){|bufrmsg|
      bufrmsg.decode_primary
      next unless bufrmsg[:cat] == 0
      case bufrmsg[:subcat]
      when 0..2, 7, 50, 51, 52
      else next
      end
      db.decode(bufrmsg, :direct, pseudo_io)
    }
  }
end
