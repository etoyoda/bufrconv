#!/usr/bin/ruby

$LOAD_PATH.push File.dirname($0)
require 'bufrdump'
require 'output'

class Bufr2synop

  def initialize out
    @hdr = @reftime = nil
    @ahl_hour = @knot = nil
    @out = out
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
    ttaaii = [tt, aa, '99'].join
    yygg = @reftime.strftime('%d%H')
    @out.startmsg(ttaaii, yygg + '00')
    # section 0
    @out.print_fold(["AAXX", "#{yygg}#{@knot ? '4' : '1'}"])
    @ahl_hour = @reftime.hour
  end

  # returns the first element
  def find tree, fxy
    for elem in tree
      if elem.first == fxy then
        return elem[1]
      elsif Array === elem.first
        ret = find(elem.first, fxy)
        return ret if ret
      end
    end
    return nil
  end

  # caution -- this does not go recursive
  def find_nth tree, fxy, nth = 2
    for elem in tree
      if fxy === elem.first then
        nth -= 1
        return elem[1] if nth.zero?
      end
    end
    return nil
  end

  def find_replication tree, containing
    tree.size.times{|i|
      elem = tree[i]
      next unless /^1/ === elem.first
      ofs = 1
      ofs += 1 if /^031/ === tree[i + ofs].first
      next if tree[i + ofs].empty?
      next unless tree[i + ofs][0].any?{|k, v| containing === k}
      return tree[i + ofs]
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

  def checkprecip tree
    precip = {}
    if rainblk = find_replication(tree, '013011') then
      rainblk.each {|subtree|
        dt = find(subtree, '004024')
	next if dt.nil? or dt == 0
	dt = -dt if dt > 0
	rv = find(subtree, '013011')
	precip[dt] = rv if rv
      }
    end
    # この時点では precp に nil は値として含まれない
    # mm (kg.m-2) 単位から Code table 3590 符号への変換
    for k in precip.keys
      rrr = (precip[k] * 10 + 0.5).floor
      rrr = case rrr
	when -1 then 990
	when 0 then 0
	when 1..9 then 990 + rrr
	# Code table 3590 は丸めについて明確ではない
	# 現状では 0.5 mm が 1 にならないことと整合的に切捨てにしている
	when 10..989.9 then (rrr / 10).to_i
	else 989
	end
      precip[k] = rrr
    end
    precip
  end

  def subset tree
    print_ahl
    report = []

    # IIiii
    _II = find(tree, '001001')
    iii = find(tree, '001002')
    report.push [itoa2(_II), itoa3(iii)].join

    # iRixhVV
    ## check precip reports
    precip = checkprecip(tree)
    iR = if precip.empty? then '4'
      elsif precip.include?(-6) and precip.size > 1 then '0'
      elsif precip.include?(-6) then '1'
      else '2'
      end

    ## check weather reports
    stntype = find(tree, '002001')
    weather = find(tree, '020003')
    case weather
    when 0..99 then 
      # present weather in Code table 4677 (ww)
      ix, ww = '1', weather
      ix = '4' if stntype.zero?
    when 508 then
      # "no significant weather as present weather"
      ix, ww = '2', nil
      # this could be ---
      # ix = '5' if stntype.zero?
      ix, ww = '7', 0 if stntype.zero?
    when 100..199 then
      # present weather in Code table 4680 (wawa)
      ix, ww = '7', weather - 100
    else
      # present weather is nil or other codes not convertible to ww
      ix, ww = '3', nil
      ix = '6' if stntype.zero?
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
    a = find(tree, '010063')
    ppp = find(tree, '010061')
    ppp = (ppp.abs + 5) / 10 if ppp
    report.push ['5', itoa1(a), itoa3(ppp)].join if a

    # 6RRRtR
    if rrr = precip[-6] then
      report.push ['6', itoa3(rrr), '1'].join
    end

    # 7wwW1W2
    w1 = find(tree, '020004')
    w2 = find(tree, '020005')
    w1 = case w1
      when 0..9 then w1
      when 10..19 then w1 - 10
      else nil
      end
    w2 = case w2
      when 0..9 then w2
      when 10..19 then w2 - 10
      else nil
      end
    report.push ['7', itoa2(ww), itoa1(w1), itoa1(w2)].join if ww or w1

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

    sec3 = ['333']

    precip.keys.reject{|h| h == -6}.each{|h|
      rrr = precip[h]
      # Code table 4019 (tR) の実装
      tr = case h
	when -12 then '2'
	when -18 then '3'
	when -24 then '4'
	when -1 then '5'
	when -2 then '6'
	when -3 then '7'
	when -9 then '8'
	when -15 then '9'
	else '0'
	end
      sec3.push ['6', itoa3(rrr), tr].join
    }

    if r24 = find(tree, '013023') then
      r24 = (r24 * 10 + 0.5).floor
      r24 = case r24
	when -1 then 9999
	when 0..9998 then r24
	else 9998
	end
      sec3.push ['7', itoa4(r24)].join
    end

    report.push(*sec3) if sec3.size > 1

    report.last.sub!(/$/, '=')
    @out.print_fold(report)
  end

  def endbufr
    return unless @ahl_hour
    @out.flush
    @hdr = @reftime = nil
    @ahl_hour = false
  end

end

if $0 == __FILE__
  db = BufrDB.new(ENV['BUFRDUMPDIR'] || File.dirname($0))
  outopts = ''
  outopts = ARGV.shift if /^-o/ =~ ARGV.first
  pseudo_io = Bufr2synop.new(Output.new(outopts))
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
