#!/usr/bin/ruby

$LOAD_PATH.push File.dirname($0)  ##del
require 'bufrdump'  ##del
require 'output'  ##del

class StatStn

  def initialize out
    @out = out
    @hdr = @ahl = nil
    @budb = Hash.new
    @buid = nil
    @n = 0
  end

  def newbufr hdr
    @hdr = hdr
    @ahl = if hdr[:meta]
      then hdr[:meta][:ahl]
      else nil
      end
    ahl = @ahl ? @ahl.split(/ /)[0,2].join : 'ahlmissing'
    ctr = hdr[:ctr] ? format('%03u', hdr[:ctr]) : "nil"
    @buid = [ctr, ahl].join(',')
  end

  def id_register idstr
    @budb[@buid] = Hash.new unless @budb.include?(@buid)
    @budb[@buid][idstr] = true
  end

  # クラス01/06/06の記述子をハッシュに集める。反復内は対象外。
  def id_collect tree
    iddb = Hash.new
    for elem in tree
      case elem.first
      when /^00[156]/
        k, v = elem
        iddb[k] = v if v
      end
    end
    iddb
  end

  def idstring iddb
    if iddb['001001'] and iddb['001002'] then
      format('%02u%03u', iddb['001001'], iddb['001002'])
    elsif iddb['001101'] and iddb['001102'] then
      format('n%03u-%u', iddb['001101'], iddb['001102'])
    elsif iddb['001007'] then
      format('s%03u', iddb['001007'])
    elsif /\w/ === iddb['001008'] then  # 001006 より優先
      'a' + iddb['001008'].strip
    elsif /\w/ === iddb['001006'] then
      'f' + iddb['001006'].strip
    elsif /\w/ === iddb['001011'] and not /\bSHIP\b/ === iddb['001011'] then
      'v' + iddb['001011'].strip
    elsif iddb['005001'] and iddb['006001'] then
      format('m%5s%6s',
        format('%+05d', (iddb['005001'] * 100 + 0.5).floor).tr('+-', 'NS'),
        format('%+06d', (iddb['006001'] * 100 + 0.5).floor).tr('+-', 'EW'))
    elsif iddb['005002'] and iddb['006002'] then
      format('p%4s%5s',
        format('%+04d', (iddb['005002'] * 10 + 0.5).floor).tr('+-', 'NS'),
        format('%+05d', (iddb['006002'] * 10 + 0.5).floor).tr('+-', 'EW'))
    else
      iddb.to_a.join('-').tr(' ', '')
    end
  end

  def subset tree
    iddb = id_collect(tree)
    return if iddb.empty?
    idx = idstring(iddb)
    id_register(idx)
    @n += 1
    if (@n % 137).zero? and $stderr.tty? then
      $stderr.printf "\r%05u", @n
      $stderr.flush
    end
  end

  def endbufr
  end

  def close
    @budb.keys.sort.each{|buid|
      puts [buid,
        @budb[buid].keys.sort.join(',')].join("\t")
    }
  end

end

if $0 == __FILE__
  db = BufrDB.setup
  encoder = StatStn.new($stdout)
  ARGV.each{|fnam|
    BUFRScan.filescan(fnam){|bufrmsg|
      db.decode(bufrmsg, :direct, encoder)
    }
  }
  encoder.close
end
