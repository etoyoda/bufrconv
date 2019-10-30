#!/usr/bin/ruby

require 'json'
$LOAD_PATH.push File.dirname($0)
require 'bufrscan'

class DataOrganizer

  def initialize mode, out = $stdout
    @mode, @out = mode, out
    # internals for :json
    @root = @tos = @tosstack = nil
    # internals for :plain
    @level = 0
  end

  def newbufr h
    case @mode
    when :json
      @out.puts JSON.generate(h)
    when :plain
      @out.puts h.inspect
    else
      raise "unsupported mode #@mode"
    end
  end

  def newsubset isubset, ptrcheck
    case @mode
    when :json
      @tosstack = []
      @tos = @root = []
    when :plain
      @out.puts "--- subset #{isubset} #{ptrcheck.inspect} ---"
      @level = 0
    end
  end

  def showval desc, val
    case @mode
    when :json
      raise "showval before newsubset" unless @tos
      @tos.push [desc[:fxy], val]
    when :plain
      @out.printf "%03u %6s %15s # %s\n", desc[:pos], desc[:fxy], val.inspect, desc[:desc]
      @out.flush if $VERBOSE
    end
  end

  def setloop
    case @mode
    when :json
      @tos.push []
      @tosstack.push @tos
      @tos = @tos.last
    when :plain
      @level += 1
      @out.puts "___ begin #@level"
    end
  end

  def newcycle
    case @mode
    when :json
      @tos = @tosstack.pop
      @tos.push []
      @tosstack.push @tos
      @tos = @tos.last
    when :plain
      @out.puts "--- next #@level"
    end
  end

  def endloop
    case @mode
    when :json
      @tos = @tosstack.pop
    when :plain
      @out.puts "^^^ end #@level"
      @level -= 1
    end
  end

  def endsubset
    case @mode
    when :json
      @out.puts JSON.generate(@root)
      @root = @tos = @tosstack = nil
    when :plain
    end
    @out.flush
  end

  def endbufr
    case @mode
    when :json
      @out.puts "7777"
    when :plain
      @out.puts "7777"
    end
  end

end

class BufrDecode

  def initialize tape, bufrmsg
    @tape, @bufrmsg = tape, bufrmsg
    @pos = nil
    # tape marker for debugging -- note a descriptor may appear twice or more
    (0 ... @tape.size).each{|i|
      @tape[i][:pos] = i
    }
    # replication counter: nesting implemented using stack push/pop
    @cstack = [{:type=>:dummy, :ctr=>-1}]
    @ymdhack = ymdhack_ini
  end

  def ymdhack_ini
    result = {}
    bits = 0
    (0 ... @tape.size).each{|i|
      desc = @tape[i]
      case desc[:fxy]
      when '004001' then
        if @tape[i+1][:fxy] == '004002' and @tape[i+2][:fxy] == '004003' then
          result[:ymd] = bits
          return result
        end
      when /^00101[15]$/ then
        result[desc[:fxy]] = bits
      when /^1..000/ then
        $stderr.puts "ymdhack failed - delayed repl before ymd" if $DEBUG
        return nil
      end
      bits += desc[:width]
    }
    $stderr.puts "ymdhack failed - ymd not found" if $DEBUG
    return nil
  end

  def rewind_tape
    @pos = -1
  end

  def forward_tape n
    @pos += n
  end

=begin
記述子列がチューリングマシンのテープであるかのように読み出す。
反復記述子がループ命令に相当する。
BUFRの反復はネストできなければいけないので（用例があるか知らないが）、カウンタ設定時に現在値はスタック構造で退避される。反復に入っていないときはダミーの記述子数カウンタが初期値-1 で入っており、１減算によってゼロになることはない。
=end

  def loopdebug title
    desc = @cstack.last
    $stderr.printf("%-7s pos=%3u nit=%-3s ctr=%-3s nds=%-3s %s\n",
      title, @pos, desc[:niter], desc[:ctr], desc[:ndesc], @cstack.size)
  end

  def read_tape_simple
    @pos += 1
    @tape[@pos]
  end

  def read_tape prt
    @pos += 1
    clast = @cstack.last
    loopdebug 'chkloop' if $VERBOSE
    if clast[:ctr].zero? then
      if clast[:niter].zero? then
        @cstack.pop
        loopdebug 'endloop' if $VERBOSE
        prt.endloop
      else
        clast[:niter] -= 1
        clast[:ctr] = clast[:ndesc] - 1
        loopdebug 'nexloop' if $VERBOSE
        prt.newcycle
        @pos -= clast[:ndesc]
      end
    else
      clast[:ctr] -= 1
    end
    @tape[@pos]
  end

  def setloop niter, ndesc
    @pos += ndesc
    @cstack.push({:niter=>niter, :ndesc=>ndesc, :ctr=>0, :resume=>@pos })
    loopdebug 'setloop' if $VERBOSE
  end

=begin
記述子列がチューリングマシンのテープであるかのように走査して処理する。
要素記述子を読むたびに、BUFR報 bufrmsg から実データを読み出す。
=end

  def run prt
    rewind_tape
    @bufrmsg.ymdhack(@ymdhack) if @ymdhack
    while desc = read_tape(prt)
      case desc[:type]
      when :str
        str = @bufrmsg.readstr(desc)
        prt.showval desc, str
      when :num
        num = @bufrmsg.readnum(desc)
        prt.showval desc, num
      when :repl
        r = desc.dup
        prt.showval r, :REPLICATION
        ndesc = r[:ndesc]
        if r[:niter].zero? then
          d = read_tape_simple
          unless d and d[:type] == :num and /^031/ === d[:fxy]
            raise "class 31 must follow delayed replication #{r.inspect}"
          end
          num = @bufrmsg.readnum(d)
          prt.showval d, num
          if num.zero? then
            setloop(0, ndesc)
            prt.setloop
          else
            setloop(num, ndesc)
            prt.setloop
          end
        else
          setloop(r[:niter], ndesc)
          prt.setloop
        end
      end
    end
  end

end

class BufrDB

  class ENOSYS < BUFRMsg::ENOSYS
  end

=begin
BUFR表BおよびDを読み込む。さしあたり、カナダ気象局の libECBUFR 付属の表が扱いやすい形式なのでこれを用いる。
=end

  def table_b_parse line
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

  def initialize dir = '.'
    table_b = File.join(dir, 'table_b_bufr')
    table_d = File.join(dir, 'table_d_bufr')
    @table_b = {}
    @table_b_v13 = {}
    @table_d = {}
    File.open(table_b, 'r:Windows-1252'){|bfp|
      bfp.each_line {|line|
        kvp = table_b_parse(line)
        @table_b[kvp[:fxy]] = kvp if kvp
      }
    }
    File.open(table_b + '.v13', 'r:Windows-1252'){|fp|
      fp.each_line {|line|
        kvp = table_b_parse(line)
        @table_b_v13[kvp[:fxy]] = kvp if kvp
      }
    }
    File.open(table_d, 'r:Windows-1252'){|bfp|
      bfp.each_line {|line|
        line.chomp!
        next if /^\s*\*/ === line
        list = line.split(/\s/)
        fxy = list.shift
        @table_d[fxy] = list
      }
    }
    @v13p = false
  end

  def tabconfig bufrmsg
    @v13p = (bufrmsg[:masver] <= 13)
    $stderr.puts "BufrDB.@v13p = #@v13p"
  end

  def table_b fxy
    return nil unless @table_b.include?(fxy)
    return @table_b_v13[fxy].dup if @v13p and @table_b_v13.include?(fxy)
    @table_b[fxy].dup
  end

=begin
記述子文字列の配列を受け取り、集約記述子を再帰的に展開し、反復記述子の修飾範囲を解析する。
出力は集約と反復が配列中配列の木構造で表現されている。
読みやすいように、集約の先頭には元の集約記述子が "#" を前置して置かれているので、 flatten してから # で始まるものを除去すれば、実際にインタプリタが駆動できるような記述子列が得られる。しかし flatten すると木構造での反復範囲の表現がわからなくなってしまうので、反復記述子は付け替えてある。
=end

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
        newx -= 1 if y.zero?
        rep.unshift format('1%02u%03u:%s', newx, y, fxy)
        result.push rep
      when /^3/ then
        raise ENOSYS, "unresolved element #{fxy}" unless @table_d.include?(fxy)
        rep = expand(@table_d[fxy])
        rep.unshift "##{fxy}"
        result.push rep
      end
    end
    result
  end

  def compile descs
    result = []
    xd = expand(descs).flatten.reject{|s| /^#/ === s}
    xd.size.times{|i|
      fxy = xd[i]
      case fxy
      when Hash then
        result.push fxy
      when /^0/ then
        desc = table_b(fxy)
        if desc
          result.push desc
        elsif result.last[:type] == :op06
          desc = { :type=>:num, :fxy=>fxy, :width=>result.last[:set_width],
            :scale =>0, :refv=>0, :desc=>"LOCAL ELEMENT #{fxy}" }
          result.push desc
        else
          raise ENOSYS, "unresolved element #{fxy}" unless desc
        end
      when /^1(\d\d)(\d\d\d):/ then
        x, y, z = $1.to_i, $2.to_i, $'
        desc = { :type => :repl, :fxy => z, :ndesc => x, :niter => y }
        result.push desc
      when /^206(\d\d\d)/ then
        y = $1.to_i
        desc = { :type => :op06, :fxy => fxy, :set_width => y }
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

  def expand_dump bufrmsg, out = $stdout
    bufrmsg.decode_primary
    out.puts JSON.pretty_generate(expand(bufrmsg[:descs].split(/[,\s]/)))
  end

  def compile_dump bufrmsg, out = $stdout
    bufrmsg.decode_primary
    tabconfig bufrmsg
    out.puts JSON.pretty_generate(compile(bufrmsg[:descs].split(/[,\s]/)))
  end

  def decode bufrmsg, outmode = :json, out = $stdout
    prt = DataOrganizer.new(outmode, out)
    bufrmsg.decode_primary
    tabconfig bufrmsg
    rc = nil
    begin
      prt.newbufr bufrmsg.to_h
      tape = compile(bufrmsg[:descs].split(/[,\s]/))
      nsubset = bufrmsg[:nsubset]
      nsubset.times{|isubset|
        begin
          prt.newsubset isubset, bufrmsg.ptrcheck
          BufrDecode.new(tape, bufrmsg).run(prt)
        ensure
          prt.endsubset
        end
      }
    rescue Errno::ENOSPC => e
      $stderr.puts e.message
      rc = 16
    ensure
      prt.endbufr
    end
    exit(rc) if rc
  end

  def decode_plain bufrmsg, out = $stdout
    decode bufrmsg, :plain, out
  end

  def decode_json bufrmsg, out = $stdout
    decode bufrmsg, :json, out
  end

end

if $0 == __FILE__
  db = BufrDB.new(ENV['BUFRDUMPDIR'] || File.dirname($0))
  action = :decode_json
  ARGV.each{|fnam|
    case fnam
    when '-x' then action = :expand_dump
    when '-c' then action = :compile_dump
    when '-d' then action = :decode_plain
    when '-j' then action = :decode_json
    else
      BUFRScan.filescan(fnam){|bufrmsg|
        db.send(action, bufrmsg)
      }
    end
  }
end
