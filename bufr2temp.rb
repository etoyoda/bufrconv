#!/usr/bin/ruby

$LOAD_PATH.push File.dirname($0)
require 'bufrdump'

class Bufr2temp

  def initialize
    @hdr = @reftime = nil
    @ahl_hour = nil
    @out = $stdout
  end

  AA = { 28=>'IN', 34=>'JP', 36=>'TH', 37=>'MO', 38=>'CI', 40=>'KR', 67=>'AU',
    110=>'HK', 116=>'KP' }

  def newbufr hdr
    @hdr = hdr
    rt = @hdr[:reftime]
    @reftime = Time.gm(rt.year, rt.mon, rt.day, rt.hour)
    gg = (rt.hour + 2) / 3 * 3
    @reftime += (3600 * (gg - rt.hour))
    @ahl_hour = false
  end

  def print_ahl
    return if @ahl_hour
    tt = 'US' # Part A
    aa = AA[@hdr[:ctr]] || 'X'
    cccc = 'RJXX'
    yygg = @reftime.strftime('%d%H')
    @out.puts "ZCZC 000     \r\r"
    @out.puts "#{tt}#{aa}99 #{cccc} #{yygg}00\r\r"
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
      if 0 != (flags & 0x08000) then
        if r[:TRP1] then
          r[:TRP2] = levset
        else 
          r[:TRP1] = levset
        end
      end
    }
    return r
  end

  STDLEVS = [
    [:SURF, '99'],
    [1000, '00'],
    [925, '92'],
    [850, '85'],
    [700, '70'],
    [500, '50'],
    [400, '40'],
    [300, '30'],
    [250, '20'],
    [200, '25'],
    [150, '15'],
    [100, '10']
  ]

  def toplevel levs
    r = nil
    for pres, id in STDLEVS
      r = id if levs.include?(pres)
    end
    return r
  end

  def subset tree
    print_ahl
    report = []

    # MiMiMjMj
    report.push "TTAA"

    # IIiii
    _II = find(tree, '001001')
    iii = find(tree, '001002')
    report.push [itoa2(_II), itoa3(iii)].join

    levbranch = branch(tree, 0)
    levels = levsort(levbranch)

    # YYGGId
    id = '1'  # do not omit ddfff until 100 hPa
    yygg = @reftime.strftime('%d%H')
    report.push [yygg, id].join

    # Section 2
    STDLEVS.each{|pres, pp|
      levset = levels[pres]

      # 99PPP or PPhhh
      case pres
      when :SURF
        ppp0 = levset ? find(levset, '007004') : nil
        ppp0 = (ppp0 / 100) % 1000 if ppp0
        report.push [pp, itoa3(ppp0)].join
      else
        hhh = levset ? find(levset, '010009') : nil
        if hhh and hhh < 0 then
          hhh = (hhh + 500.5).to_i
        elsif hhh and pres > 500 then
          hhh = (hhh * 10).to_i % 1000
        elsif hhh then
          hhh = (hhh + 0.5).to_i % 1000
        end
        report.push [pp, itoa3(hhh)].join
      end

      # TTTaDD
      ttt = levset ? find(levset, '012101') : nil
      td = levset ? find(levset, '012103') : nil
      _DD = (ttt && td) ? ttt - td : nil
      if ttt and ttt >= 273.15
        ttt = ((ttt - 273.15) * 5).to_i * 2
      elsif ttt
        ttt = ((273.15 - ttt) * 5).to_i * 2 + 1
      end
      if _DD and _DD <= 5.0 then
        _DD = (_DD * 10).to_i
      elsif _DD then
        _DD = (_DD + 0.5).to_i
      end
      report.push [itoa3(ttt), itoa2(_DD)].join

      # ddfff
      dd = levset ? find(levset, '011001') : nil
      fff = levset ? find(levset, '011002') : nil
      dd = ((dd + 2.5) / 5).to_i * 5 if dd
      fff = (fff + 0.5).to_i if fff
      if dd and 0 != (dd % 10) then
        fff += 500 if fff
      end
      dd /= 10 if dd
      report.push [itoa2(dd), itoa3(fff)].join
    }

=begin
    report.push '61616 DEBUG'
    maxws = branch(tree, 1)
    report.push "MAXW#{maxws ? maxws.size : '/'}"
=end

    @out.puts report.join(' ') + "=\r\r"
  end

  def endbufr
    return unless @ahl_hour
    @out.puts "\n\n\n\n\n\n\n\nNNNN\r\r"
    @hdr = @reftime = nil
    @ahl_hour = false
  end

end

if $0 == __FILE__
  db = BufrDB.new(ENV['BUFRDUMPDIR'] || File.dirname($0))
  pseudo_io = Bufr2temp.new
  ARGV.each{|fnam|
    BUFRScan.filescan(fnam){|bufrmsg|
      bufrmsg.decode_primary
      next unless bufrmsg[:cat] == 2
      case bufrmsg[:subcat]
      when 4..7
      else next
      end
      db.decode(bufrmsg, :direct, pseudo_io)
    }
  }
end
