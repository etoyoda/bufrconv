#!/usr/bin/ruby
#
# usage: ruby stnstat.rb time sfctime.txt < statin.txt > statout.txt
#

require 'time'
require 'json'

def diag str
  STDERR.puts str if STDERR.tty?
end

time = Time.parse(ARGV.shift)
stime = time.utc.strftime('%Y-%m-%dT%H:%MZ')
diag "select time #{stime}"

db = Hash.new
STDIN.each_line {|line|
  ent = JSON.parse(line)
  next unless ent.include?('@')
  db[ent['@']] = ent
}

VFACTOR = 0.01

for line in ARGF
  key, jdata = line.chomp.split(/ /, 2)
  itime, ilev, istn = key.split(/\//, 3)
  next unless ilev == 'sfc'
  next unless itime == stime
  next if /^gpv/ === istn
  data = JSON.parse(jdata)
  unless db[istn]
    db[istn] = {'@'=>istn, 'tf'=>stime, 'av'=>1.0, 'at'=>nil,
      'tv'=>1.0, 'tt'=>nil, 'pv'=>1.0, 'pt'=>nil, }
  end
  ent = db[istn]
  ent['at'] = stime
  ent['av'] = ent['av'] * (1.0 - VFACTOR) + 1.0 * VFACTOR
  ent['tt'] = stime if data['T']
  ent['av'] = ent['av'] * (1.0 - VFACTOR) + (data['T'] ? 1.0 : 0.0) * VFACTOR
  ent['pt'] = stime if data['P']
  ent['pv'] = ent['pv'] * (1.0 - VFACTOR) + (data['P'] ? 1.0 : 0.0) * VFACTOR
end

for stn in db.keys
  next if db[stn]['at'] == stime
  ent['av'] = ent['av'] * (1.0 - VFACTOR)
  ent['tv'] = ent['tv'] * (1.0 - VFACTOR)
  ent['pv'] = ent['pv'] * (1.0 - VFACTOR)
end

for stn in db.keys
  STDOUT.puts JSON.generate(db[stn])
end
