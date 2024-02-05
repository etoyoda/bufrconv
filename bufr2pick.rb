#!/usr/bin/ruby

$LOAD_PATH.push File.dirname($0) ##del
require 'bufrdump' ##del

class Bufr2pick

  class ENOMSG < Errno::ENOMSG
  end

  def initialize
    @hdr = @reftime = nil
  end

  def newbufr hdr
    @hdr = hdr
    rt = @hdr[:reftime]
    @reftime = Time.gm(rt.year, rt.mon, rt.day, rt.hour)
    gg = (rt.hour + 2) / 3 * 3
    @reftime += (3600 * (gg - rt.hour))
    @sreftime = @reftime.strftime('%Y%m%dT%H%MZ')
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

  def stnname idx
    name = case idx
      when 47401 then "_Wakkanai"
      when 47412 then "_Sapporo"
      when 47418 then "_Kushiro"
      when 47582 then "_Akita"
      when 47600 then "_Wajima"
      when 47646 then "_Tateno"
      when 47678 then "_Hachijojima"
      when 47741 then "_Matsue"
      when 47778 then "_Shionomisaki"
      when 47807 then "_Fukuoka"
      when 47827 then "_Kagoshima"
      when 47909 then "_Naze"
      when 47918 then "_Ishigakijima"
      when 47945 then "_Minamidaitojima"
      when 47971 then "_Chichijima"
      when 47991 then "_Minamitorishima"
      when 89532 then "_Syowa"
      else ""
      end
    return format("%05u%s", idx, name)
  end

  def report title, spres, selem, val
    return if val.nil?
    printf("%s,%2s,+0,+0,%-5s,-0,%20s,%8.2f\n", @sreftime, selem, spres,title,val)
  end

  def tetens t
    6.112 * Math::exp(17.67 * (t - 273.15) / (t - 29.65))
  end

  def subset tree

    # 地点名
    _II = find(tree, '001001')
    iii = find(tree, '001002')
    idx = _II * 1000 + iii
    title = stnname(idx)

    branch(tree, 0).each{|levset|
      flags = find(levset, '008042')
      # 指定面・圏界面・特異面・最大風速面いがいのフラグなし面は捨てる
      next if flags.zero?
      pres = find(levset, '007004')
      spres = format('p%u', pres * 0.01)
      report(title, spres, 'Z', find(levset, '010009'))
      t = find(levset, '012101')
      td = find(levset, '012103')
      if (t and td) then 
        rh = tetens(td)/tetens(t)*100.0
        report(title, spres, 'T', t)
        report(title, spres, 'Td', td)
        report(title, spres, 'RH', rh)
      end
      d = find(levset, '011001')
      f = find(levset, '011002')
      if (d and f) then
        drad = d / 180.0 * 3.14159
  #     report(title, spres, 'WD', d)
        report(title, spres, 'U', -f*Math::sin(drad))
        report(title, spres, 'V', -f*Math::cos(drad))
      end
    }

  rescue ENOMSG => e
    $stderr.puts [e.message.sub(/.* - /, ''), given_ahl()].join(' ')
  end

  def endbufr
  end

  def close
  end

end

if $0 == __FILE__
  db = BufrDB.setup
  # コマンドラインオプションは最初の引数だけ
  outopts = if /^-o/ =~ ARGV.first then ARGV.shift else '' end
  encoder = Bufr2pick.new()
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
