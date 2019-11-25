#!/usr/bin/ruby

$LOAD_PATH.push File.dirname($0)  ##del
require 'bufrdump'  ##del
require 'output'  ##del

class Bufr2synop

  def initialize out
    @hdr = @reftime = nil
    @ahl_hour = @knot = nil
    @out = out
  end

  def newbufr hdr
    @hdr = hdr
    rt = @hdr[:reftime]
    @reftime = Time.gm(rt.year, rt.mon, rt.day, rt.hour)
    @reftime += 3600 if rt.min > 0
    @ahl_hour = @knot = false
  end

  def given_ahl default = nil
    return default unless @hdr
    return default unless @hdr[:meta]
    @hdr[:meta][:ahl] or default
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
    case @hdr[:ctr]
    when 34 then
      @knot = true
    end
    yygg = @reftime.strftime('%d%H')
    @out.startmsg(tt, yygg + '00', @hdr)
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
    rdata = {}
    precip = []
    if rainblk = find_replication(tree, '013011') then
      rainblk.each {|subtree|
        dt = find(subtree, '004024')
        next if dt.nil? or dt == 0
        # 記述子 004024 には負値を記載せねばならないが (B/C1.10.3.2)
        # 誤って正で通報している例がみられるので救済
        dt = -dt if dt > 0
        rv = find(subtree, '013011')
        rdata[dt] = rv if rv
      }
    end
    # この時点では rdata に nil は値として含まれない
    rdata.keys.each{|dt|
      # mm (kg.m-2) 単位から Code table 3590 (RRR) への変換
      # to_i で丸めると -0.1 が 0 になってしまうので不可
      rrr = (rdata[dt] * 10 + 0.5).floor
      rrr = case rrr
        # 990 が微量 trace をあらわす
        when -1 then 990
        when 0 then 0
        when 1..9 then 990 + rrr
        # Code table 3590 は丸めに方向について明確ではない
        # 現状では 0.5 mm が 1 にならないことと整合的に切捨てにしている
        when 10..989.9 then (rrr / 10).to_i
        else 989
        end
      # Code table 4019 (tR) の実装
      tr = case dt
        when -12 then '2'
        when -18 then '3'
        when -24 then '4'
        when -1 then '5'
        when -2 then '6'
        when -3 then '7'
        when -9 then '8'
        when -15 then '9'
        # 表にない間隔の場合も省略はしない。利用価値はないだろうが。
        else '0'
        end
      precip.push ['6', itoa3(rrr), tr].join
    }
    precip
  end

  def temperature indicator, kelvin
    case kelvin
    when 173.25 ... 273.15
      [indicator, '1', itoa3(((273.2 - kelvin) * 10).to_i)].join
    when 273.15 ... 373.05
      [indicator, '0', itoa3(((kelvin - 273.1) * 10).to_i)].join
    else
      [indicator, '////'].join
    end
  end

  def subset tree
    report = []

    # IIiii
    _II = find(tree, '001001')
    iii = find(tree, '001002')
    # 地点番号が欠けていたら通報にならないので変換中止
    if _II.nil? or iii.nil?
      $stderr.printf("missing IIiii ed%s c%s-%s %s\n",
        itoa1(@hdr[:ed]), itoa3(@hdr[:cat]), itoa3(@hdr[:subcat]),
        given_ahl.inspect)
      return
    end
    stnid = [itoa2(_II), itoa3(iii)].join
    report.push stnid
    print_ahl
    @out.station(stnid)

    # 現地気圧と気温の両方が欠損しているときは全欠損とみなす。
    # see https://github.com/etoyoda/bufrconv/issues/10
    if find(tree, '010004').nil? and find(tree, '012101').nil? then
      report.push "NIL"
    else

      # iRixhVV
      # 記述子 013011 の降水量に12時間または6時間のものがあれば第１節に、
      # 残りは第３節に記載する。厳密には地区毎に取り決めが違いうるがさしあたり。
      precip3 = checkprecip(tree)
      precip1 = []
      if precip3.any?{|desc| /2$/ === desc} then
        precip1 = precip3.grep(/2$/)
        precip3 = precip3.reject{|desc| /2$/ === desc}
      elsif precip3.any?{|desc| /1$/ === desc} then
        precip1 = precip3.grep(/1$/)
        precip3 = precip3.reject{|desc| /1$/ === desc}
      end

      iR = if precip1.empty? and precip3.empty? then '4'
        elsif precip1.empty? then '2'
        elsif precip3.empty? then '1'
        else '0'
        end

      # 内的整合性による補正
      # 第１節および第３節 6RRRtR 群に反映すべき情報がなく、
      # 12時間または6時間の降水有無を知ることができない場合でも、
      # 24時間降水量が非欠損で 0.0 mm または trace であれば、
      # 指示符 iR を降水なしの '3' とする。
      r24 = find(tree, '013023')
      if iR == '4' and r24 and r24 <= 0.0 then
        iR = '3'
      end

      ## check weather reports
      stntype = find(tree, '002001')
      stntype = 0 if stntype.nil?
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
      # 雲底高度： 020013 の最大値は 20060 m
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
        when 2500 ... 99999 then 9
        else nil
        end
      # 視程： 020001 の最大値は 81900 m
      vis = find(tree, '020001')
      _VV = case vis
        when 0..5000 then ((vis + 50) / 100).to_i
        when 5000..30_000 then ((vis + 50500) / 1000).to_i
        when 30_000..70_000 then ((vis - 30_000) / 5000).to_i + 80
        when 70_000..99_000 then 89
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
      report.push temperature('1', _TTT)

      # 2snTdTdTd
      _TdTdTd = find(tree, '012103')
      report.push temperature('2', _TdTdTd)

      # 3P0P0P0P0 現地気圧
      _P0P0P0P0 = find(tree, '010004')
      _P0P0P0P0 = ((_P0P0P0P0 + 5) / 10) % 1000_0 if _P0P0P0P0 
      report.push ['3', itoa4(_P0P0P0P0)].join if _P0P0P0P0 

      # 4PPPP 海面気圧
      _PPPP = find(tree, '010051')
      _PPPP = ((_PPPP + 5) / 10) % 1000_0 if _PPPP 
      # 海面気圧が欠けていればジオポテンシャルを探す。
      # (規則 B/C1.3.5.1 により海面気圧が算出できない地点で与えらえる)
      # また海面気圧の先頭桁が 1..8 になる場合、つまり 1100 hPa 以上または
      # 900 hPa 未満の場合は、ジオポテンシャル形式にしないと解読不能になる
      if _PPPP.nil? or (_PPPP > 100_0 and _PPPP < 900_0) then
        a3 = find(tree, '007004')
        a3 = case a3
          when 1000_00 then '1'
          when 925_00 then '2'
          when 850_00 then '8'
          when 700_00 then '7'
          when 500_00 then '5'
          else nil
          end
        hhh = find(tree, '010009')
        hhh = hhh % 1000 if hhh
        report.push ['4', a3, itoa3(hhh)].join if a3
      else
        report.push ['4', itoa4(_PPPP)].join if _PPPP 
      end

      # 5appp 気圧変化傾向
      a = find(tree, '010063')
      ppp = find(tree, '010061')
      ppp = (ppp.abs + 5) / 10 if ppp
      report.push ['5', itoa1(a), itoa3(ppp)].join if a

      # 6RRRtR 降水量、12時間または6時間
      report.push(*precip1)

      # 7wwW1W2 現在天気と過去天気
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
      # 通報中に 020011 は多数あるが、最初のものが Nh で残りは Ns である
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

      # --- 第3節 ---
      sec3 = ['333']

      # 1snTxTxTx - 最高気温
      # 期間は地区決定しだいであるがTACには表現不能、データがあれば落とさず出す
      tx = find(tree, '012111')
      sec3.push temperature('1', tx) if tx

      # 2snTnTnTn - 最低気温
      # 期間は地区決定しだいであるがTACには表現不能、データがあれば落とさず出す
      tn = find(tree, '012112')
      sec3.push temperature('2', tn) if tn

      # 3snTgTgTg - 地表最低気温
      # 通報形式が地区次第で、そちらの資料は未見
      if tg = find(tree, '012113') then
        if tg < 273.15 then
          tg = ((273.2 - tg) * 10).floor
          sec3.push ['3', '1', itoa3(tg)].join
        else
          tg = ((tg - 273.1) * 10).floor
          sec3.push ['3', '0', itoa3(tg)].join
        end
      end

      # 4E'sss - 積雪深
      _E_ = find(tree, '020062')
      _E_ = case _E_
        when 10..19 then _E_ - 10
        else nil
        end
      sss = find(tree, '013013')
      sss = (sss * 100 + 0.5).floor if sss
      sss = 996 if sss and sss > 996
      if sss == -1 then
        # 0.5 cm 以下の積雪がある
        sss = 997
      elsif sss == -2 then
        # 不連続な積雪がある
        sss = 998
        # 仮に _E_ の値が矛盾したとしても、さしあたり、あえて修正しない
      end
      unless sss
        # 積雪深が欠損で来そうな場合でも地面状態で値を設定することあり
        case _E_
        # 998 連続していない積雪
        when 11, 12, 15, 16 then sss = 998
        # 999 測定不能な場合（E' により積雪があることがわかるので）
        when 13, 14, 17..19 then sss = 999
        end
      end
      sss = nil if 0 == sss and _E_.nil? and stntype.zero?
      sec3.push ['4', itoa1(_E_), itoa3(sss)].join if _E_ or sss

      # 6RRRtR
      sec3.push(*precip3)

      # 7R24R24R24R24
      if r24 then
        r24 = (r24 * 10 + 0.5).floor
        r24 = case r24
          when -1 then 9999
          when 0..9998 then r24
          else 9998
          end
        sec3.push ['7', itoa4(r24)].join
      end

      report.push(*sec3) if sec3.size > 1

    end

    report.last.sub!(/$/, '=')
    @out.print_fold(report)
  rescue NoMethodError => e
    $stderr.puts [e.message, e.backtrace.first, @hdr[:meta].inspect].join(' ')
  end

  def endbufr
    return unless @ahl_hour
    @out.flush
    @hdr = @reftime = nil
    @ahl_hour = false
  end

  def close
    @out.close
  end

end

if $0 == __FILE__
  db = BufrDB.new(ENV['BUFRDUMPDIR'] || File.dirname($0))
  # コマンドラインオプションは最初の引数だけ
  outopts = if /^-o/ =~ ARGV.first then ARGV.shift else '' end
  encoder = Bufr2synop.new(Output.new(outopts, db.path))
  ARGV.each{|fnam|
    BUFRScan.filescan(fnam){|bufrmsg|
      bufrmsg.decode_primary
      next unless bufrmsg[:cat] == 0
      case bufrmsg[:subcat]
      when 0..2, 7, 50, 51, 52
      else next
      end
      db.decode(bufrmsg, :direct, encoder)
    }
  }
  encoder.close
end
