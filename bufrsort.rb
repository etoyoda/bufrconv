#!/usr/bin/ruby

require 'json'

$LOAD_PATH.push File.dirname($0)  ##del
require 'bufrdump'  ##del
require 'output'  ##del

class BufrSort

  def initialize spec
    @fn = 'zsort.txt'
    @now = Time.now.utc
    @limit = 30
    if spec.nil?
      $stderr.puts "usage: ruby #{$0} default,FN:#{@fn},LM:30 files ..."
      exit 16
    end
    for param in spec.split(/,/)
      case param
      when /^(default|-)/i then :do_nothing
      when /^unlim$/i then @limit = Float::INFINITY
      when /^FN:(\S+)/i then @fnpat = $1
      when /^LM:(\d+)/i then @limit = $1.to_i
      when /^LM:(\d+)D/i then @limit = $1.to_i * 24
      else raise "unknown param #{param}"
      end
    end
    @hdr = nil
    @ofp = File.open(@fn, 'a:UTF-8')
    @nsubset = @nstore = 0
    @verbose = nil
  end

  def verbose!
    @verbose = true
  end

  def newbufr hdr
    @hdr = hdr
  end

  # 反復の外にある記述子を集める
  def shallow_collect tree
    shdb = Hash.new
    for elem in tree
      case elem.first
      when String
        k, v = elem
	v = v.to_f if Rational === v
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

  def shdbtime shdb
    y = shdb['004001']
    y += 2000 if y < 100
    t = Time.gm(y, shdb['004002'], shdb['004003'], shdb['004004'],
      shdb['004005'] || 0,
      shdb['004006'] || 0)
    return t
  rescue
    return nil
  end

  def surface shdb, idx
    t = shdbtime(shdb)
    return if t.nil?
    k = t.strftime('%Y-%m-%dT%H:00Z/sfc/') + idx
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
    @nstore += 1
    @ofp.puts [k, JSON.generate(r)].join(' ')
  end

  def subset tree
    @nsubset += 1
    if (@nsubset % 137).zero? and $stderr.tty? then
      $stderr.printf("subset %6u\r", @nsubset)
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
  end

  def close
    @ofp.close 
    $stderr.printf("subset %6u store %6u\n", @nsubset, @nstore) if @verbose
  end

end

if $0 == __FILE__
  db = BufrDB.setup
  encoder = BufrSort.new(ARGV.shift)
  encoder.verbose! if $stderr.tty?
  ARGV.each{|fnam|
    BUFRScan.filescan(fnam){|bufrmsg|
      db.decode(bufrmsg, :direct, encoder)
    }
  }
  encoder.close
end
