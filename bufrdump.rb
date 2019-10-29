#!/usr/bin/ruby

require 'json'
$LOAD_PATH.push File.dirname($0)
require 'bufrscan'

class BufrDecode

  def initialize tape, bufrmsg
    @tape, @bufrmsg = tape, bufrmsg
    @pos = nil
    # tape marker for debugging -- note a descriptor may appear twice or more
    (0 ... @tape.size).each{|i|
      @tape[i][:pos] = i
    }
    # replication counter: nesting implemented using stack push/pop
    @cstack = [{:type=>:dummy, :ctr=>0}]
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
    @pos = 0
  end

  def forward_tape n
    @pos += n
  end

=begin
記述子列がチューリングマシンのテープであるかのように読み出す。
反復記述子がループ命令に相当する。反復記述子を読むと、
反復数カウンタ clast[:niter] と
記述子数カウンタ clast[:ctr] が設定される。
ループ内の記述子を読み出した後で、記述子数カウンタは１減算される。
記述子数カウンタをゼロにするとき、反復数カウンタが１減算される。
反復数カウンタが１減算の結果非零になるならば、読み出し位置が戻される。
記述子数カウンタのループ先頭での設定値や読み出し位置の戻し幅には、遅延反復記述子を計算に入れない。
反復数カウンタが１減算の結果ゼロになるならば、反復が終了する。
BUFRの反復はネストできなければいけないので（用例があるか知らないが）、カウンタ設定時に現在値はスタック構造で退避される。反復に入っていないときはダミーの記述子数カウンタが初期値ゼロで入っており、１減算によってゼロになることはない。
=end

  def loopdebug title, desc, opt = ''
    $stderr.printf("%-7s pos=%3u niter=%-3s ctr=%-3s ndesc=%-3s %s\n",
      title, @pos, desc[:niter], desc[:ctr], desc[:ndesc], opt)
  end

  def read_tape(keep_ctr = false)
    clast = @cstack.last
    loopdebug 'chkloop', clast, "keep_ctr=#{keep_ctr.inspect}" if $VERBOSE
    d = @tape[@pos]
    @pos += 1
    return d if keep_ctr
    clast[:ctr] -= 1
    if clast[:ctr].zero? then
      clast[:niter] -= 1
      if clast[:niter].zero? then
        @cstack.pop
        loopdebug 'endloop', clast if $VERBOSE
      else
        clast[:ctr] = clast[:ndesc]
        @pos -= clast[:ndesc]
        loopdebug 'nexloop', clast if $VERBOSE
      end
    end
    d
  end

  def setloop desc
    loopdebug 'setloop', desc if $VERBOSE
    @cstack.push desc
  end

  def showval out, desc, val = nil
    out.printf "%03u %6s %15s # %s\n", desc[:pos], desc[:fxy], val.inspect, desc[:desc]
    out.flush if $VERBOSE
  end

=begin
記述子列がチューリングマシンのテープであるかのように走査して処理する。
要素記述子を読むたびに、BUFR報 bufrmsg から実データを読み出す。
=end

  def run out = $stdout
    rewind_tape
    @bufrmsg.ymdhack(@ymdhack) if @ymdhack
    while desc = read_tape
      case desc[:type]
      when :str
        str = @bufrmsg.readstr(desc)
        showval out, desc, str
      when :num
        num = @bufrmsg.readnum(desc)
        showval out, desc, num
      when :repl
        r = desc.dup
        showval out, r, :REPLICATION
        if r[:niter].zero? then
          d = read_tape(:keep_ctr)
          unless d and d[:type] == :num and /^031/ === d[:fxy]
            raise "class 31 must follow delayed replication #{r.inspect}"
          end
          num = @bufrmsg.readnum(d)
          showval out, d, num
          if num.zero? then
            forward_tape(r[:ndesc])
            r[:niter] = r[:ctr] = 1
          else
            r[:niter] = num
            r[:ctr] = r[:ndesc]
          end
        else
          r[:ctr] = r[:ndesc]
        end
        setloop r
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

  def initialize dir = '.'
    table_b = File.join(dir, 'table_b_bufr')
    table_d = File.join(dir, 'table_d_bufr')
    @b = {}
    @d = {}
    File.open(table_b, 'r'){|bfp|
      bfp.each_line {|line|
        line.chomp!
        next if /^\s*\*/ === line
        fxy = line[0, 6]
        units = line[52, 10].strip
        type = case units when 'CCITT IA5' then :str else :num end
        kvp = {:type => type, :fxy => fxy}
        kvp[:desc] = line[8, 43].strip
        kvp[:units] = units
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
    xd.size.times{|i|
      fxy = xd[i]
      case fxy
      when Hash then
        result.push fxy
      when /^0/ then
        if @b.include?(fxy)
          desc = @b[fxy].dup
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
    out.puts JSON.pretty_generate(compile(bufrmsg[:descs].split(/[,\s]/)))
  end

  def decode bufrmsg, out = $stdout
    bufrmsg.decode_primary
    puts bufrmsg.inspect
    tape = compile(bufrmsg[:descs].split(/[,\s]/))
    nsubset = bufrmsg[:nsubset]
    nsubset.times{|isubset|
      puts "--- subset #{isubset} #{bufrmsg.ptrcheck.inspect} ---"
      begin
        BufrDecode.new(tape, bufrmsg).run(out)
      rescue => e
        $stderr.puts e.message
        break
      end
    }
  end

end

if $0 == __FILE__
  db = BufrDB.new(ENV['BUFRTABDIR'] || File.dirname($0))
  action = :decode
  ARGV.each{|fnam|
    case fnam
    when '-x' then action = :expand_dump
    when '-c' then action = :compile_dump
    when '-d' then action = :decode
    else
      BUFRScan.filescan(fnam){|bufrmsg|
        db.send(action, bufrmsg)
      }
    end
  }
end
