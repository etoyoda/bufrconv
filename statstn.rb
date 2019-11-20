#!/usr/bin/ruby

$LOAD_PATH.push File.dirname($0)  ##del
require 'bufrdump'  ##del
require 'output'  ##del

class StatStn

  def initialize out
    @out = out
    @hdr = @ahl = nil
    @budb = Hash.new
    @buid = nil
    @n = 0
  end

  def newbufr hdr
    @hdr = hdr
    @ahl = if hdr[:meta]
      then hdr[:meta][:ahl]
      else nil
      end
    ahl = @ahl ? @ahl.split(/ /)[0,2].join : 'ahlmissing'
    ctr = hdr[:ctr] ? format('%03u', hdr[:ctr]) : "nil"
    @buid = [ctr, ahl].join(',')
  end

  def id_register idstr
    @budb[@buid] = Hash.new unless @budb.include?(@buid)
    @budb[@buid][idstr] = true
  end

  # returns the first element
  def id_collect tree
    iddb = Hash.new
    for elem in tree
      if /^001/ === elem.first
        iddb[elem.first] = elem[1]
      end
    end
    iddb
  end

  def subset tree
    iddb = id_collect(tree)
    if iddb['001001'] and iddb['001002'] then
      idx = format('%02u%03u', iddb['001001'], iddb['001002'])
      id_register(idx)
    end
    @n += 1
    if (@n % 137).zero? then
      $stderr.printf "\r%05u", @n
      $stderr.flush
    end
  end

  def endbufr
  end

  def close
    @budb.keys.sort.each{|buid|
      puts [buid,
        @budb[buid].keys.sort.join(',')].join("\t")
    }
  end

end

if $0 == __FILE__
  db = BufrDB.new(ENV['BUFRDUMPDIR'] || File.dirname($0))
  encoder = StatStn.new($stdout)
  ARGV.each{|fnam|
    BUFRScan.filescan(fnam){|bufrmsg|
      bufrmsg.decode_primary
      db.decode(bufrmsg, :direct, encoder)
    }
  }
  encoder.close
end
