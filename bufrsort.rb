#!/usr/bin/ruby

require 'json'

$LOAD_PATH.push File.dirname($0)  ##del
require 'bufrdump'  ##del
require 'output'  ##del

class BufrSort

  def initialize spec
    @fn = 'zsort.txt'
    @now = Time.now.utc
    @amdar = false
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
      when /^AMDAR$/i then @amdar = true
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

  # pres に最も近い指定面気圧を返す
  def stdpres pres, flags
    # 鉛直レベル意義フラグが存在して指定面ではない場合は門前払いする。
    if flags then
      return nil if (flags & 0x10000).zero?
    end
    stdp = case pres
      when 900_00..950_00 then
        925_00
      when 0...75_00 then
        ((pres + 5_00) / 10_00).floor * 10_00
      else
        ((pres + 25_00) / 50_00).floor * 50_00
      end
    case stdp
    when 1050_00, 950_00, 900_00, 800_00, 750_00, 650_00, 600_00,
    550_00, 450_00, 350_00, 80_00, 60_00, 40_00, 0 then
      return nil
    else
      stdp
    end
  end

  LB = -6.5e-3
  GMU_RL = 9.80665 * 28.9644e-3 / 8.31432 / LB

  def barometric z, tref
    101325 * (tref / (tref + LB * z)) ** GMU_RL
  end

  def stdpres_z z, flags, lat
    tref = [[323.7 - lat.abs, 300].min, 273].max
    pres = barometric(z, tref)
    stdp = stdpres(pres, flags)
    return nil if stdp.nil?
    [stdp, (pres - stdp).abs]
  end

  def upperlevel levcollect, lat = 35.55
    h = Hash.new
    if pres = levcollect['007004'] then
      stdp = stdpres(pres, levcollect['008042'])
      return nil if stdp.nil?
      h[:pst] = stdp
      h[:bad] = (pres - stdp).abs
      # ほんとは測高公式で補正すべきなんだが、とりあえず
      h[:z] = levcollect['010009'] if h[:bad] < 30
    elsif z = (levcollect['007009'] || levcollect['007010'] ||
    levcollect['007002'] || levcollect['007007']) then
      h[:pst], h[:bad] = stdpres_z(z, levcollect['008042'], lat)
      return nil if h[:pst].nil?
    elsif z = levcollect['007006'] then
      z += levcollect['007001'].to_f
      h[:pst], h[:bad] = stdpres_z(z, nil, lat)
      return nil if h[:pst].nil?
    else
      return nil
    end
    h[:T] = levcollect['012101'] if levcollect.include?('012101')
    h[:Td] = levcollect['012103'] if levcollect.include?('012103')
    if d = levcollect['011001'] and f = levcollect['011002'] then
      h[:d] = d
      h[:f] = f
    elsif u = levcollect['011003'] and v = levcollect['011004'] then
      f = Math::hypot(u, v)
      d = Math::atan2(u, v) / Math::PI * 180 + 180
      h[:d] = Rational(((d * 100 + 5) / 10).floor, 10).to_f
      h[:f] = Rational(((f * 100 + 5) / 10).floor, 10).to_f
    else
      return nil
    end
    h[:dLa] = levcollect['005015'] if levcollect.include?('005015')
    h[:dLo] = levcollect['006015'] if levcollect.include?('006015')
    h
  end

  def upper tree, idx, shdb
    t = shdbtime(shdb)
    # hack for Japan wind profiler
    if t.nil? and shdb['001001'] == 47 then
      tbranch = branch(tree, 0)
      return if tbranch.nil?
      t = shdbtime(shallow_collect(tree = tbranch.last))
    end
    return if t.nil?
    t = Time.at((t.to_i / 3600).floor * 3600).utc
    t += 3600 if t.hour % 3 == 2
    stdlevs = {}
    lat = (shdb['005001'] || shdb['005002'])
    return if lat.nil?
    if shdb['011001'] then
      h = upperlevel(shdb)
      return if h.nil?
      stdp = h[:pst]
      h.delete(:pst)
      stdlevs[stdp] = h
    else
      levbranch = branch(tree, 0)
      return if levbranch.nil?
      levbranch.each{|slice|
        h = upperlevel(shallow_collect(slice), lat)
        next if h.nil?
        stdp = h[:pst]
        h.delete(:pst)
        if stdlevs[stdp].nil? or stdlevs[stdp][:bad] > h[:bad] then
          stdlevs[stdp] = h
        end
      }
    end
    stdlevs.each{|stdp, r|
      r[:La] = lat
      r[:La] += r[:dLa] if r[:dLa]
      r.delete(:dLa)
      next unless r[:Lo] = (shdb['006001'] || shdb['006002'])
      r[:Lo] += r[:dLo] if r[:dLo]
      r.delete(:dLo)
      r.delete(:bad)
      r["@"] = idx
      lev = format('p%u', stdp / 100)
      k = [t.strftime('%Y-%m-%dT%H:00Z'), lev, idx].join('/') 
      @nstore += 1
      @ofp.puts [k, JSON.generate(r)].join(' ')
    }
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
    when 0, 1 then
      surface(shdb, idx)
    when 2 then
      upper(tree, idx, shdb)
    when 4 then
      upper(tree, idx, shdb) if @amdar
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
