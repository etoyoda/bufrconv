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
    # corrections
    isocode = 'ATA' if '7' === region
    idxnum = format('%05u', wigosid.split(/-/,4)[3].to_i % 100000) if idxnum.empty?
    raise "isocode=#{isocode} (#{line})" unless /^[A-Z]{3}$/ === isocode
    raise "idxnum=#{idxnum} (#{line})" unless /^[0-9]{5}$/ === idxnum
    aa = isoaa[isocode]
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
