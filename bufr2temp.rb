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

  def levsort levbranch
    r = {}
    levbranch.each{|levset|
      flags = find(levset, '008042')
      pres = find(levset, '007004')
      pres = (pres / 100).to_i if pres
      r[pres] = levset if 0 != (flags & 0x10000)
      r[:SURF] = levset if 0 != (flags & 0x20000)
      r[:MAXW] = levset if 0 != (flags & 0x04000)
      if 0 != (flags & 0x08000) and pres and pres > 100 then
        if r[:TRP1] and not r[:TRP2] then
          r[:TRP2] = levset
        else 
          r[:TRP1] = levset
        end
      end
    }
    return r
  end

  STDLEVS = [
    [:SURF, '99', '/'],
    [1000, '00', '0'],
    [925, '92', '9'],
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
    # levels to be included in the result
    stdlevs = nil
    id = '1'
    # first levels missing in BUFR are omitted
    for pres, pp, pid in STDLEVS
      next if :SURF === pres
      if levdb.include? pres
        stdlevs = [] unless stdlevs
      end
      stdlevs.push([pres, pp]) if stdlevs
    end
    raise ENOMSG, "No std level" if stdlevs.nil?
    stdlevs.unshift STDLEVS.first
    return stdlevs, id
  end

  def encode_level report, pres, pp, levset

    # 99PPP or PPhhh
    case pres
    when :SURF, :TRP1, :TRP2, :MAXW
      ppp = levset ? find(levset, '007004') : nil
      ppp *= 10 if ppp and ppp < 100_00
      ppp = (ppp / 100) % 1000 if ppp
      report.push [pp, itoa3(ppp)].join
    else
      hhh = levset ? find(levset, '010009') : nil
      if hhh and hhh < 0 then
        hhh = (hhh + 500.5).to_i
      elsif hhh and pres > 500 then
        hhh = hhh.to_i % 1000
      elsif hhh then
        hhh = ((hhh + 5) / 10).to_i % 1000
      end
      report.push [pp, itoa3(hhh)].join
    end

    # TTTaDD
    unless '77' == pp
      ttt = levset ? find(levset, '012101') : nil
      td = levset ? find(levset, '012103') : nil
      _DD = (ttt && td) ? ttt - td : nil
      if ttt then
        if ttt >= 273.15
          ttt = ((ttt - 273.15) * 5).to_i * 2
        else
          ttt = ((273.20 - ttt) * 5).to_i * 2 + 1
        end
      end
      if _DD then
        if _DD < 5.0 then
          _DD = (_DD * 10).to_i
        elsif _DD < 5.5 then
          _DD = 50
        else
          _DD = (_DD + 50.5).to_i
        end
      end
      report.push [itoa3(ttt), itoa2(_DD)].join
    end

    # ddfff
    dd = levset ? find(levset, '011001') : nil
    fff = levset ? find(levset, '011002') : nil
    fff *= 1.9438 if fff and @knot
    dd = ((dd + 2.5) / 5).to_i * 5 if dd
    fff = (fff + 0.5).to_i if fff
    if dd and 0 != (dd % 10) then
      fff += 500 if fff
    end
    dd /= 10 if dd
    if dd == 31 and fff == 313 then
      $stderr.puts "31314 for dd=31 and fff=313 to avoid unparseable"
      fff = 314
    end
    report.push [itoa2(dd), itoa3(fff)].join
  end

  def subset tree
    report = []

    # MiMiMjMj
    report.push "TTAA "

    levbranch = branch(tree, 0)
    levdb = levsort(levbranch)
    stdlevs, id = scanlevs(levdb)

    # YYGGId
    yy = find(tree, '004003') || @reftime.day
    yy += 50 if @knot
    _GG1 = find(tree, '004004') || @reftime.hour
    report.push [itoa2(yy), itoa2(_GG1), id].join

    # IIiii
    _II = find(tree, '001001')
    iii = find(tree, '001002')
    stnid = [itoa2(_II), itoa3(iii)].join
    report.push stnid

    set_ahl
    @out.tell_station stnid

    # Section 2
    stdlevs.each{|pres, pp|
      levset = levdb[pres]
      encode_level(report, pres, pp, levset)
    }

    encode_level(report, :TRP1, '88', levdb[:TRP1]) if levdb[:TRP1]
    encode_level(report, :TRP2, '88', levdb[:TRP2]) if levdb[:TRP2]
    report.push '88999' unless levdb[:TRP1]

    encode_level(report, :MAXW, '77', levdb[:MAXW]) if levdb[:MAXW]
    report.push '77999' unless levdb[:MAXW]

    # 4vbvbvava not implemented - considered deprecated not having real example

    report.push '31313'

    # srrarasasa
    sr = find(tree, '002013')
    sr -= 2 if (8..9) === sr
    rara = find(tree, '002011')
    rara = case rara
      when 0..99 then rara
      when 100..199 then rara - 100
      else nil
      end
    sasa = find(tree, '002014')
    report.push [itoa1(sr), itoa2(rara), itoa2(sasa)].join

    # 8GGgg
    _GG = find(tree, '004004')
    gg = find(tree, '004005')
    report.push ['8', itoa2(_GG), itoa2(gg)].join

    report.last.sub!(/$/, '=')
    @out.print_fold(report)
  rescue ENOMSG => e
    $stderr.puts [e.message.sub(/.* - /, ''), given_ahl()].join(' ')
  end

  def given_ahl
    @hdr.ahl
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
      next unless bufrmsg[:cat] == 2
      case bufrmsg[:subcat]
      when 4..7
      else next
      end
      db.decode(bufrmsg, :direct, encoder)
    }
  }
  encoder.close
end
