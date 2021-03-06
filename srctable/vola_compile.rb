#!/usr/bin/ruby

db5 = Hash.new
db4 = Hash.new
db3 = Hash.new

def check_store hash, key, val
  case hash[key]
  when false
    return
  when String
    if hash[key] != val then
      hash[key] = false
    end
  else
    hash[key] = val
  end
end

unless File.exist?('vola_legacy_report.txt')
  cmd = "wget https://oscar.wmo.int/oscar/vola/vola_legacy_report.txt"
  system(cmd)
end

isoaa = {}
File.open('iso3166-gtsaa.txt', 'r'){|fp|
  fp.each_line{|line|
    next if /^#/ === line
    line.chomp!
    row = line.split(/\t/)
    if isoaa.include? row[1] then
      raise "dup entry [#{row[1]}] ... #{isoaa[row[1]]} vs #{row[0]}"
    end
    isoaa[row[1]] = row[0]
  }
}

File.open('vola_legacy_report.txt', 'r:UTF-8'){|fp|
  fp.each_line{|line|
    next if /^RegionId/ === line
    line.chomp!
    row = line.split(/\t/)
    region = row[0]
    isocode = row[3]
    wigosid = row[4]
    idxnum = row[5]
    name = row[7]
    lat = row[8]
    lon = row[9]
    next if idxnum.empty?
    # corrections
    isocode = 'ATA' if '7' === region
    raise "isocode=#{isocode} (#{line})" unless /^[A-Z]{3}$/ === isocode
    isocode = 'PT-20' if 'PRT' == isocode and /ACORES/ === name
    if '1' == region then
      isocode = 'PT-30' if 'PRT' == isocode
      isocode = 'ES-CN' if 'ESP' == isocode
      if 'GBR' == isocode then
        isocode = case name
          when /ASCENSION/ then 'SH-AC'
          when /ST\. HELENA/ then 'SH-HL'
          when /DIEGO GARCIA/ then 'IOT'
          end
      end
      isocode = 'REU' if 'FRA' == isocode
      isocode = 'BVT' if 'NOR' == isocode
    end
    if '2' == region then
      isocode = 'RU-KHA' if 'RUS' == isocode
    end
    if '3' == region then
      isocode = 'FLK' if 'GBR' == isocode
      isocode = 'GUF' if 'FRA' == isocode
    end
    if '4' == region then
      isocode = 'ATG' if 'GBR' == isocode
      isocode = 'BLM' if 'FRA' == isocode
      isocode = 'BES' if 'NLD' == isocode
      isocode = 'US-AK' if 'USA' == isocode and /^1[3-7]/ === lon
    end
    if '5' == region then
      isocode = 'WLF' if 'FRA' == isocode
    end
    raise "idxnum=#{idxnum} (#{line})" unless /^[0-9]{5}$/ === idxnum
    aa = isoaa[isocode]
    aa = 'PA' if '5' == region and /^(US|FM|MH|PP)$/ === aa
    aa = 'PA' if 'AK' == aa and /E$/ === lon
    raise "undefined AA for #{isocode} (#{line})" unless aa
    db5[idxnum] = aa
    check_store(db4, idxnum[0,4], aa)
    check_store(db3, idxnum[0,3], aa)
  }
}

db3.keys.sort.each {|idx3|
  if db3[idx3] then
    puts "#{idx3}..\t#{db3[idx3]}"
    next
  end
  ('0' .. '9').each{|digit4|
    idx4 = idx3 + digit4
    if db4[idx4] then
      puts "#{idx4}.\t#{db4[idx4]}"
      next
    end
    ('0' .. '9').each{|digit5|
      idx5 = idx4 + digit5
      puts "#{idx5}\t#{db5[idx5]}" if db5[idx5]
    }
  }
}
