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

  # 反復の外にある記述子を集める
  def shallow_collect tree
    shdb = Hash.new
    for elem in tree
      case elem.first
      when String
        k, v = elem
        shdb[k] = v if v
      end
    end
    shdb
  end

  def idstring shdb
    if shdb['001001'] and shdb['001002'] then
      format('%02u%03u', shdb['001001'], shdb['001002'])
    elsif shdb['001101'] and shdb['001102'] then
      format('n%03u-%u', shdb['001101'], shdb['001102'])
    elsif shdb['001007'] then
      format('s%03u', shdb['001007'])
    elsif /\w/ === shdb['001008'] then  # 001006 より優先
      'a' + shdb['001008'].strip
    elsif /\w/ === shdb['001006'] then
      'f' + shdb['001006'].strip
    elsif /\w/ === shdb['001011'] and not /\bSHIP\b/ === shdb['001011'] then
      'v' + shdb['001011'].strip
    elsif shdb['005001'] and shdb['006001'] then
      format('m%5s%6s',
        format('%+05d', (shdb['005001'] * 100 + 0.5).floor).tr('+-', 'NS'),
        format('%+06d', (shdb['006001'] * 100 + 0.5).floor).tr('+-', 'EW'))
    elsif shdb['005002'] and shdb['006002'] then
      format('p%4s%5s',
        format('%+04d', (shdb['005002'] * 10 + 0.5).floor).tr('+-', 'NS'),
        format('%+05d', (shdb['006002'] * 10 + 0.5).floor).tr('+-', 'EW'))
    else
      shdb.to_a.join('-').tr(' ', '')
    end
  end

  def surface shdb, idx
    k = format('sfc/%04u-%02u-%02uT%02uZ/%s',
      shdb['004001'],
      shdb['004002'],
      shdb['004003'],
      shdb['004004'],
      idx)
    r = Hash.new
    r['@'] = idx
    r['La'] = (shdb['005001'] || shdb['005002'])
    r['Lo'] = (shdb['006001'] || shdb['006002'])
    r['V'] = shdb['020001']
    r['N'] = shdb['020010']
    r['d'] = shdb['011001']
    r['f'] = shdb['011002']
    r['T'] = shdb['012101']
    r['Td'] = shdb['012103']
    r['P0'] = shdb['010004']
    r['P'] = shdb['010051']
    r['p'] = shdb['010061']
    r['w'] = shdb['020003']
    r['s'] = shdb['013013']
    @dbf[k] = JSON.generate(r)
  end

  def subset tree
    # 日付があわないときは @dbf == nil とされている
    return if @dbf.nil?
    @n += 1
    if (@n % 173).zero? and $stderr.tty? then
      $stderr.printf "\rsort %6u\r", @n
      $stderr.flush
    end
    shdb = shallow_collect(tree)
    return if shdb.empty?
    idx = idstring(shdb)
    case @hdr[:cat]
    when 0
      surface(shdb, idx)
    end
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
