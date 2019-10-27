#!/usr/bin/ruby

$LOAD_PATH.push File.dirname($0)
require 'bufrscan'

class BUFRDump

  def initialize table_b, table_d
    @b = {}
    @d = {}
    File.open(table_b, 'r'){|bfp|
      bfp.each_line {|line|
        line.chomp!
        next if /^\s*\*/ === line
        fxy = line[0, 6]
        kvp = {}
        kvp[:units] = line[52, 10].strip
        kvp[:scale] = line[62, 4].to_i
        kvp[:refv] = line[66, 11].to_i
        kvp[:width] = line[77, 6].to_i
        kvp[:nbits] = ('CCITT IA5' == kvp[:units]) ? kvp[:width] * 8 : kvp[:width]
        kvp[:desc] = line[8, 43].strip
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
    descs.each{|fxy|
      if @d.include? fxy then
        result.push expand(@d[fxy])
      else
        result.push fxy
      end
    }
    result
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

  def expand_explain descs, out = $stdout
    expand(descs).flatten.each {|fxy|
      out.puts explain_fxy(fxy)
    }
  end

end

if $0 == __FILE__
  dumper = BUFRDump.new('table_b_bufr', 'table_d_bufr')
  ARGV.each{|fnam|
    BUFRScan.filescan(fnam){|msg|
      msg.decode_primary
      puts msg[:fnam]
      descs = msg[:descs].split(/[,\s]/)
      dumper.expand_explain(descs)
    }
  }
end
