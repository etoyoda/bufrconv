#!/usr/bin/ruby

require 'gdbm'
require 'json'

$LOAD_PATH.push File.dirname($0)  ##del
require 'bufrdump'  ##del
require 'output'  ##del

class BufrSort

  def initialize spec
    @fnpat = 'bf%Y-%m-%d.db'
    @limit = 30
    for param in spec.split(/,/)
      case param
      when 'default' then :do_nothing
      when /^FN:(\S+)/ then @fnpat = $1
      when /^LM:(\d+)/ then @limit = $1.to_i
      else
      end
    end
    @hdr = nil
    @dbf = nil
    @files = {}
    @now = Time.now.utc
    @n = 0
  end

  def opendb reftime
    dbfnam = reftime.utc.strftime(@fnpat)
    @files[dbfnam] = true
    @dbf = GDBM.open(dbfnam, 0666, GDBM::WRCREAT)
  end

  def newbufr hdr
    @hdr = hdr
    if (@now - hdr[:reftime]) > (@limit * 3600) then
      $stderr.puts "skip reftime #{hdr[:reftime]}"
      @dbf = nil
      return
    end
    opendb(hdr[:reftime])
  end

  def id_register tree, idstr
    rec = @hdr.to_h.dup
    rec.delete(:descs)
    rec[:data] = tree
    key = [@hdr[:reftime].utc.strftime('%Y-%m-%dT%HZ'), idstr].join('/')
    @dbf[key] = JSON.generate(rec)
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
    # 日付があわないときは @dbf == nil とされている
    return if @dbf.nil?
    @n += 1
    if (@n % 173).zero? and $stderr.tty? then
      $stderr.printf "\rsort %6u\r", @n
      $stderr.flush
    end
    iddb = id_collect(tree)
    return if iddb.empty?
    idx = idstring(iddb)
    id_register(tree, idx)
  end

  def endbufr
    # 日付があわないときは @dbf == nil とされている
    @dbf.close if @dbf
    @dbf = nil
  end

  def close
    raise 'BUG' if @dbf
    $stderr.puts("wrote: " + @files.keys.join(' '))
  end

end

if $0 == __FILE__
  db = BufrDB.setup
  encoder = BufrSort.new(ARGV.shift)
  ARGV.each{|fnam|
    BUFRScan.filescan(fnam){|bufrmsg|
      db.decode(bufrmsg, :direct, encoder)
    }
  }
  encoder.close
end
