#!/usr/bin/ruby
require 'json'
db = Hash.new
for line in ARGF
  shdr, sbody = line.split(/ /, 2)
  body = JSON.parse(sbody)
  hdr = shdr.split(/\//, 3)
  id = [hdr[0], hdr[1], body['La'].to_i, body['Lo'].to_i].join('/')
  if not db.include?(id) then
    db[id] = [hdr[2], line]
  elsif hdr[2] < db[id][0] then
    db[id] = [hdr[2], line]
  end
end
db.each_value {|line|
  puts line
}
