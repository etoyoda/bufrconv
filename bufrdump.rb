#!/usr/bin/ruby

require 'json'
if __FILE__ == $0
  $LOAD_PATH.push File.dirname($0)
  require 'bufrscan'
end

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
    when :direct
      @out.newbufr h
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
    when :json, :direct
      @tosstack = []
      @tos = @root = []
    when :plain
      @out.puts "=== subset #{isubset} #{ptrcheck.inspect} ==="
      @level = 0
    end
  end

  def showval desc, val
    case @mode
    when :json, :direct
      raise "showval before newsubset" unless @tos
      @tos.push [desc[:fxy], val]
    when :plain
      sval = if val and :flags === desc[:type]
        then format(format('0x%%0%uX', (desc[:width]+3)/4), val)
        else val.inspect
        end
      @out.printf "%6s %15s #%03u %s\n", desc[:fxy], sval, desc[:pos], desc[:desc]
      @out.flush if $VERBOSE
    end
  end

  def setloop
    case @mode
    when :json, :direct
      @tos.push []
      @tosstack.push @tos
      @tos = @tos.last
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
    when :json, :direct
      @tos = @tosstack.pop
      @tos.pop if @tos.last.empty?
      @tos.push []
      @tosstack.push @tos
      @tos = @tos.last
    when :plain
      @out.puts "--- next #@level"
    end
  end

  def endloop
    case @mode
    when :json, :direct
      @tos = @tosstack.pop
      @tos.pop if @tos.last.empty?
      @tos = @tosstack.pop
    when :plain
      @out.puts "^^^ end #@level"
      @level -= 1
    end
  end

  def endsubset
    case @mode
    when :direct
      @out.subset @root
      @root = @tos = @tosstack = nil
    when :json
      @out.puts JSON.generate(@root)
      @root = @tos = @tosstack = nil
      @out.flush
    when :plain
      @out.flush
    end
  end

  def endbufr
    case @mode
    when :direct
      @out.endbufr
    when :json
      @out.puts "7777"
    when :plain
      @out.puts "7777"
    end
  end

end

class BufrDecode

  class ENOSYS < BUFRMsg::ENOSYS
  end

  def initialize tape, bufrmsg
    @tape, @bufrmsg = tape, bufrmsg
    @pos = nil
    # replication counter: nesting implemented using stack push/pop
    @cstack = []
    # operators
    @addwidth = @addscale = @addfield = nil
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
    @addwidth = @addscale = @addfield = nil
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
    $stderr.printf("%-7s pos=%3u %s\n",
      title, @pos, @cstack.inspect)
  end

  def read_tape_simple
    @pos += 1
    @tape[@pos]
  end

  def read_tape prt
    @pos += 1
    loopdebug 'read_tape1' if $VERBOSE
    if @tape[@pos].nil? then
      loopdebug "ret-nil-a" if $VERBOSE
      return nil
    end

    while :endloop == @tape[@pos][:type]
      # quick hack workaround
      if @cstack.empty? then
        $stderr.puts "skip :endloop pos=#{@pos} #{@bufrmsg.ahl}"
        break
      end
      @cstack.last[:count] -= 1
      if @cstack.last[:count] > 0 then
        # 反復対象記述子列の最初に戻る。
	# そこに :endloop はないので while を抜ける
        @pos = @cstack.last[:next]
        prt.newcycle
        loopdebug 'nextloop' if $VERBOSE
      else
        # 当該レベルのループを終了し :endloop の次に行く。
	# そこに :endloop があれば while が繰り返される。
        @cstack.pop
        @pos += 1
        prt.endloop
        loopdebug 'endloop' if $VERBOSE
        if @tape[@pos].nil? then
          loopdebug "ret-nil-b" if $VERBOSE
          return nil
        end
      end
    end
    #
    # operators
    #
    ent = @tape[@pos]
    if @addwidth and :num === ent[:type] then
      ent = ent.dup
      ent[:width] += @addwidth
    end
    if @addscale and :num === ent[:type] then
      ent = ent.dup
      ent[:scale] += @addscale
    end
    ent
  end

  def setloop niter, ndesc
    loopdebug 'setloop1' if $VERBOSE
    @cstack.push({:next => @pos + 1, :niter => niter, :count => niter})
    if niter.zero? then
      @pos += ndesc
    end
    loopdebug 'setloop2' if $VERBOSE
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
        if @addfield then
          @addfield[:pos] = desc[:pos]
	  num = @bufrmsg.readnum(@addfield)
          prt.showval @addfield, num
        end
        str = @bufrmsg.readstr(desc)
        prt.showval desc, str
      when :num, :code, :flags
        if @addfield and not /^031021/ === desc[:fxy] then
          @addfield[:pos] = desc[:pos]
	  num = @bufrmsg.readnum(@addfield)
          prt.showval @addfield, num
        end
        num = @bufrmsg.readnum(desc)
        prt.showval desc, num
      when :repl
        r = desc.dup
        prt.showval r, :REPLICATION
        ndesc = r[:ndesc]
        if r[:niter].zero? then
          d = read_tape_simple
          unless d and /^031/ === d[:fxy]
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
      when :op01
        if desc[:yyy].zero? then
          @addwidth = nil
        else
          @addwidth = desc[:yyy] - 128
        end
      when :op02
        if desc[:yyy].zero? then
          @addscale = nil
        else
          @addscale = desc[:yyy] - 128
        end
      when :op04
        if desc[:yyy].zero? then
          @addfield = nil
        else
          raise ENOSYS, "nested 204YYY" if @addfield
          @addfield = { :type => :code,
            :width => desc[:yyy], :scale => 0, :refv => 0,
            :units => 'CODE TABLE', :desc => 'ASSOCIATED FIELD',
            :pos => -1, :fxy => desc[:fxy]
          }
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
    type = case units
      when 'CCITT IA5' then :str
      when 'CODE TABLE' then :code
      when 'FLAG TABLE' then :flags
      else :num
      end
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
    raise ENOSYS, "master version missing" unless bufrmsg[:masver]
    @v13p = (bufrmsg[:masver] <= 13)
    $stderr.puts "BufrDB.@v13p = #@v13p" if $DEBUG
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
        rep.push "#END #{newx}"
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
    xd = expand(descs).flatten.reject{|s| /^#3/ === s}
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
          desc = {
            :type=>:num, :fxy=>fxy, :width=>result.last[:set_width],
            :scale =>0, :refv=>0, :desc=>"LOCAL ELEMENT #{fxy}",
            :units =>"NUMERIC"
          }
          result.push desc
        else
          raise ENOSYS, "unresolved element #{fxy}" unless desc
        end
      when /^1(\d\d)(\d\d\d):/ then
        x, y, z = $1.to_i, $2.to_i, $'
        desc = { :type => :repl, :fxy => z, :ndesc => x, :niter => y }
        result.push desc
      when /^#END (\d+)/ then
        desc = { :type => :endloop, :ndesc => $1.to_i }
        result.push desc
      when /^201(\d\d\d)/ then
        result.push({ :type => :op01, :fxy => fxy, :yyy => $1.to_i })
      when /^202(\d\d\d)/ then
        result.push({ :type => :op02, :fxy => fxy, :yyy => $1.to_i })
      when /^204(\d\d\d)/ then
        result.push({ :type => :op04, :fxy => fxy, :yyy => $1.to_i })
      when /^205(\d\d\d)/ then
        result.push({ :type => :str, :fxy => fxy, :width=>$1.to_i * 8,
          :scale=>0, :refv=>0, :desc=>"OPERATOR #{fxy}", :units=>'CCITT IA5' })
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
    # デバッグ用位置サイン
    (0 ... result.size).each{|i|
      result[i][:pos] = i
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

  # raises ENOSPC
  def decode bufrmsg, outmode = :json, out = $stdout
    prt = DataOrganizer.new(outmode, out)
    bufrmsg.decode_primary
    tabconfig bufrmsg
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
      $stderr.puts e.message + bufrmsg[:meta].inspect
    ensure
      prt.endbufr
    end
  end

  # raises ENOSPC
  def decode_plain bufrmsg, out = $stdout
    decode bufrmsg, :plain, out
  end

  # raises ENOSPC
  def decode_json bufrmsg, out = $stdout
    decode bufrmsg, :json, out
  end

end

if $0 == __FILE__
  db = BufrDB.new(ENV['BUFRDUMPDIR'] || File.dirname($0))
  case ARGV.first
  when '-xstr' then ARGV.shift; puts JSON.generate(db.expand(ARGV)); exit
  when '-cstr' then ARGV.shift; puts JSON.generate(db.compile(ARGV)); exit
  end
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
