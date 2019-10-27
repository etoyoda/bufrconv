#!/usr/bin/ruby

require 'json'
$LOAD_PATH.push File.dirname($0)
require 'bufrscan'

class BufrDecode

  def initialize tape, bufrmsg
    @tape, @bufrmsg = tape, bufrmsg
    @ptr = 0
    @cstack = []
  end

  def run
  end

end

class BufrDB

  class ENOSYS < BUFRMsg::ENOSYS
  end

  def initialize table_b, table_d
    @b = {}
    @d = {}
    File.open(table_b, 'r'){|bfp|
      bfp.each_line {|line|
        line.chomp!
        next if /^\s*\*/ === line
        fxy = line[0, 6]
        kvp = {:type => :elem, :fxy => fxy}
        kvp[:desc] = line[8, 43].strip
        kvp[:units] = line[52, 10].strip
        kvp[:scale] = line[62, 4].to_i
        kvp[:refv] = line[66, 11].to_i
        kvp[:width] = line[77, 6].to_i
        @b[fxy] = kvp
      }
    }
    File.open(table_d, 'r'){|bfp|
      bfp.each_line {|line|
        line.chomp!
        next if /^\s*\*/ === line
        list = line.split(/\s/)
        fxy = list.shift
        @d[fxy] = list
      }
    }
  end

  def expand descs
    result = []
    a = descs.dup
    while fxy = a.shift
      case fxy
      when /^[02]/ then
        result.push fxy
      when /^1(\d\d)(\d\d\d)/ then
        x = $1.to_i
        y = $2.to_i
        x += 1 if y.zero?
        rep = expand(a.shift(x))
        newx = rep.flatten.reject{|s|/^#/ === s}.size
        rep.unshift format('1%02u%03u:%s', newx, y, fxy)
        result.push rep
      when /^3/ then
        raise ENOSYS, "unresolved element #{fxy}" unless @d.include?(fxy)
        rep = expand(@d[fxy])
        rep.unshift "##{fxy}"
        result.push rep
      end
    end
    result
  end

  def compile descs
    result = []
    xd = expand(descs).flatten.reject{|s| /^#/ === s}
    xd.each{|fxy|
      case fxy
      when Hash then
        result.push fxy
      when /^0/ then
        desc = @b[fxy]
        raise ENOSYS, "unresolved element #{fxy}" unless desc
        result.push desc
      when /^1(\d\d)(\d\d\d):/ then
        x, y, z = $1.to_i, $2.to_i, $'
        desc = { :type => :repl, :fxy => z, :ndesc => x, :niter => y }
        result.push desc
      when /^2/ then
        raise ENOSYS, "unsupported operator #{fxy}"
      when /^3/ then
        raise ENOSYS, "unresolved sequence #{fxy}"
      else
        raise ENOSYS, "unknown fxy=#{fxy}"
      end
    }
    return result
  end

  def explain_fxy fxy
    desc = @b[fxy]
    case fxy
    when /^1(\d\d)000/ then
      return "#{fxy},,,,repeat following #{$1} descriptors variable times"
    when /^1(\d\d)(\d\d\d)/ then
      return "#{fxy},,,,repeat following #{$1} descriptors #{$2} times"
    end
    raise "unknown desc #{fxy}" unless desc
    [fxy, desc[:scale], desc[:refv], desc[:width], desc[:desc]].join(',')
  end

  def expand_dump bufrmsg, out = $stdout
    bufrmsg.decode_primary
    out.puts JSON.pretty_generate(expand(bufrmsg[:descs].split(/[,\s]/)))
  end

  def compile_dump bufrmsg, out = $stdout
    bufrmsg.decode_primary
    out.puts JSON.pretty_generate(compile(bufrmsg[:descs].split(/[,\s]/)))
  end

  def decode bufrmsg, out = $stdout
    bufrmsg.decode_primary
    tape = compile(bufrmsg[:descs].split(/[,\s]/))
    BufrDecode.new(tape, bufrmsg, out).run
  end

end

if $0 == __FILE__
  db = BufrDB.new('table_b_bufr', 'table_d_bufr')
  action = :decode
  ARGV.each{|fnam|
    case fnam
    when '-x' then action = :expand_dump
    when '-c' then action = :compile_dump
    else
      BUFRScan.filescan(fnam){|bufrmsg|
        db.send(action, bufrmsg)
      }
    end
  }
end
