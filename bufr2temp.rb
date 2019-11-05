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

    # MiMiMjMj
    report.push "TTAA"

    # IIiii
    _II = find(tree, '001001')
    iii = find(tree, '001002')
    report.push [itoa2(_II), itoa3(iii)].join

    # YYGGId
    id = '1' # toriaezu
    yygg = @reftime.strftime('%d%H')
    report.push [yygg, id].join

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
