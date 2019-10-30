#!/usr/bin/ruby

def readfile fnam
  db = {}
  File.open(fnam, 'r:Windows-1252'){|fp|
    fp.each_line {|line|
      next if /^\s*\*/ === line
      ary = line.strip.split(/\s+/)
      seq = ary.shift
      db[seq] = ary.join(' ')
    }
  }
  return db
end

db1 = readfile(ARGV.shift)
db2 = readfile(ARGV.shift)

for fxy, seq1 in db1
  seq2 = db2[fxy]
  next unless seq2
  next if seq1 == seq2
  if $VERBOSE then
    puts ['<', fxy, seq1].join(' ')
    puts ['>', fxy, seq2].join(' ')
  else
    puts [fxy, seq1].join(' ')
  end
end
