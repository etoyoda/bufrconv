#!/usr/bin/ruby

$LOAD_PATH.push File.dirname($0)
require 'bufrdump'

class Bufr2synop

  def initialize
    @hdr = @reftime = nil
    @ahl_done = nil
    @out = $stdout
  end

  AA = { 28=>'IN', 34=>'JP', 36=>'TH', 37=>'MO', 38=>'CI', 40=>'KR', 67=>'AU',
    110=>'HK', 116=>'KP' }

  def newbufr hdr
    @hdr = hdr
    rt = @hdr[:reftime]
    @reftime = Time.gm(rt.year, rt.mon, rt.day, rt.hour)
    @reftime += 3600 if rt.min > 0
    @ahl_done = false
  end

  def print_ahl
    return if @ahl_done
    tt = case @reftime.hour
      when 0, 12 then 'SM'
      when 6, 18 then 'SI'
      else 'SN'
      end
    aa = AA[@hdr[:ctr]] || 'XX'
    cccc = 'RJXX'
    yygg = @reftime.strftime('%d%H')
    @out.puts "ZCZC"
    @out.puts "#{tt}#{aa}99 #{cccc} #{yygg}00"
    @out.puts "AAXX #{yygg}1"
    @ahl_done = true
  end

  def subset tree
    # data category 0: Surface data - land
    return if @hdr[:cat] != 0
    print_ahl
    @out.puts tree.inspect

  end

  def endbufr
    @out.puts "NNNN"
  end

end

if $0 == __FILE__
  db = BufrDB.new(ENV['BUFRDUMPDIR'] || File.dirname($0))
  pseudo_io = Bufr2synop.new
  ARGV.each{|fnam|
    BUFRScan.filescan(fnam){|bufrmsg|
      db.decode(bufrmsg, :direct, pseudo_io)
    }
  }
end
