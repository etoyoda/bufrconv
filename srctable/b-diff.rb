def parse line
  return nil if /^\s*\*/ === line
  fxy = line[0, 6]
  units = line[52, 10].strip
  type = case units when 'CCITT IA5' then :str else :num end
  kvp = {:type => type, :fxy => fxy}
  kvp[:desc] = line[8, 43].strip
  kvp[:units] = units
  kvp[:scale] = line[62, 4].to_i
  kvp[:refv] = line[66, 11].to_i
  kvp[:width] = line[77, 6].to_i
  return kvp
end


def file fnam
  db = {}
  File.open(fnam, 'r:Windows-1252'){|fp|
    fp.each_line {|line|
      desc = parse(line)
      next if desc.nil?
      db[desc[:fxy]] = desc
    }
  }
  db
end

db1 = file(ARGV.shift)
db2 = file(ARGV.shift)

for fxy, d1 in db1
  d2 = db2[fxy]
  next unless d2
  if d1[:scale] == d2[:scale] and d1[:refv] == d2[:refv] and d1[:width] == d2[:width]
    next
  end
  printf("%6s  %-43s %-10s%4d%11d%6d\n", fxy, d2[:desc], d2[:units],
    d1[:scale], d1[:refv], d1[:width])
end
