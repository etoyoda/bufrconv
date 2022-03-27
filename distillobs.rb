#!/usr/bin/ruby
require 'json'
db = Hash.new
for line in ARGF
  shdr, sbody = line.split(/ /, 2)
  next unless sbody
  body = JSON.parse(sbody)
  hdr = shdr.split(/\//, 3)
  id = [hdr[0], hdr[1], body['La'].to_i, body['Lo'].to_i].join('/')
  body['La'] = (body['La'] * 100).floor * 0.01
  body['Lo'] = (body['Lo'] * 100).floor * 0.01
  for var in body.keys - ['N', 'd', 'f']
    next unless body.include?(var)
    body.delete(var) if body[var].nil?
  end
  body['N'] = nil unless body.include?('N')
  sbody = JSON.generate(body).gsub(/000000+\d,/, ',')
  line = [shdr, sbody].join(' ')
  if not db.include?(id) then
    db[id] = [hdr[2], line]
  elsif hdr[2] < db[id][0] then
    db[id] = [hdr[2], line]
  end
end
db.each_value {|stnid, line|
  puts line
}
