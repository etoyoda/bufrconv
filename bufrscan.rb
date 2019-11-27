#!/usr/bin/ruby

=begin
BUFRテーブルの読み込みなしでできる程度の解読。

単独で起動した場合
  ruby bufrscan.rb files ...
  ruby bufrscan.rb -d files ...
=end

class BUFRMsg

  def self.unpack1(str)
    str.unpack('C').first
  end

  def self.unpack2(str)
    str.unpack('n').first
  end

  def self.unpack3(str)
    ("\0" + str).unpack('N').first
  end

  class EBADF < Errno::EBADF
  end

  class ENOSYS < Errno::ENOSYS
  end

  class ENOSPC < Errno::ENOSPC
  end

  def initialize buf, ofs, msglen, fnam = '-', ahl = nil
    @buf, @ofs, @msglen, @fnam, @ahl = buf, ofs, msglen, fnam, ahl
    @ed = @buf[ofs+7].unpack('C').first
    @props = {
      :msglen => @msglen, :ed => @ed,
      :meta => { :ahl => @ahl, :fnam => @fnam, :ofs => @ofs }
    }
    @ptr = nil
    @ymdhack = {}
    build_sections
  end

  def build_sections
    #
    # building section structure with size validation
    #
    esofs = @ofs + @msglen - 4
    @idsofs = @ofs + 8
    @idslen = BUFRMsg::unpack3(@buf[@idsofs, 3])
    opsflag = case @ed
      when 4
        BUFRMsg::unpack1(@buf[@idsofs + 9]) >> 7
      when 3, 2
        BUFRMsg::unpack1(@buf[@idsofs + 7]) >> 7
      else
        raise ENOSYS, "unsupported BUFR edition #{@ed}"
      end
    if opsflag != 0 then
      @opsofs = @idsofs + @idslen
      raise EBADF, "OPS #{@opsofs} beyond msg end #{esofs}" if @opsofs >= esofs
      @opslen = BUFRMsg::unpack3(@buf[@opsofs,3])
      @ddsofs = @opsofs + @opslen
    else
      @opsofs = nil
      @opslen = 0
      @ddsofs = @idsofs + @idslen
    end
    raise EBADF, "DDS #{@ddsofs} beyond msg end #{esofs}" if @ddsofs >= esofs
    @ddslen = BUFRMsg::unpack3(@buf[@ddsofs,3])
    @dsofs = @ddsofs + @ddslen
    raise EBADF, "DS #{@dsofs} beyond msg end #{esofs}" if @dsofs >= esofs
    @dslen = BUFRMsg::unpack3(@buf[@dsofs,3])
    esofs2 = @dsofs + @dslen
    raise EBADF, "ES #{esofs2} mismatch msg end #{esofs}" if esofs2 != esofs
    @ptr = (@dsofs + 4) * 8
    @ptrmax = @ptr + (@dslen - 4) * 8
  end

  def dump ofs = nil
    ofs = @dsofs unless ofs
    8.times {
      printf "%5u:", ofs
      8.times {
        printf " %08b", @buf[ofs].unpack('C').first
        ofs += 1
      }
      printf "\n"
    }
  end

  def ptrcheck
    [@ptr, @ptrmax]
  end

  def ptrseek ofs
    @ptr += ofs
  end

  def peeknum ptr, width
    ifirst = ptr / 8
    raise ENOSPC, "peeknum #{ifirst} out of msg size #{@buf.bytesize}" if ifirst > @buf.bytesize
    ilast = (ptr + width) / 8
    iwidth = ilast - ifirst + 1
    ishift = 8 - ((ptr + width) % 8)
    imask = ((1 << width) - 1) << ishift
    ival = @buf[ifirst,iwidth].unpack('C*').inject{|r,i|(r<<8)|i}
    [iwidth, ishift, imask, ival]
  end

  def getnum ptr, width
    iwidth, ishift, imask, ival = peeknum(ptr, width)
    (imask & ival) >> ishift
  end

  def readnum2 desc
    width, scale, refv = desc[:width], desc[:scale], desc[:refv]
    do_missing = !(/^(031|204)/ === desc[:fxy])
    if @ptr + width + 6 > @ptrmax
      raise ENOSPC, "end of msg reached #{@ptrmax} < #{@ptr} + #{width} + 6"
    end
    # reference value R0
    iwidth, ishift, imask, ival = peeknum(@ptr, width)
    @ptr += width
    n = getnum(@ptr, 6)
    @ptr += 6
    if ival & imask == imask and do_missing then
      raise "difference #{n} bits cannot follow missing value R0" if n != 0
      return [nil] * nsubset
    end
    r0 = ((imask & ival) >> ishift) + refv
    # data array
    rval = [r0] * nsubset
    if n > 0 then
      nsubset.times{|i|
        kwidth, kshift, kmask, kval = peeknum(@ptr, n)
        @ptr += n
        if kval & kmask == kmask and do_missing then
          rval[i] = nil
        else
          rval[i] += ((kmask & kval) >> kshift)
          rval[i] = rval[i].to_f * (10.0 ** -scale) unless scale.zero?
        end
      }
    end
    return rval
  end

  def readnum desc
    return readnum2(desc) if compressed?
    width, scale, refv = desc[:width], desc[:scale], desc[:refv]
    do_missing = !(/^(031000|031031|204)/ === desc[:fxy])
    if @ptr + width > @ptrmax
      raise ENOSPC, "end of msg reached #{@ptrmax} < #{@ptr} + #{width}"
    end
    iwidth, ishift, imask, ival = peeknum(@ptr, width)
    @ptr += width
    if ival & imask == imask and do_missing then
      return nil
    end
    rval = ((imask & ival) >> ishift) + refv
    rval = rval.to_f * (10.0 ** -scale) unless scale.zero?
    rval
  end

  def readstr1 width
    len = width / 8
    if @ptr + width > @ptrmax
      raise ENOSPC, "end of msg reached #{@ptrmax} < #{@ptr} + #{width}"
    end
    ifirst = @ptr / 8
    ilast = (@ptr + width - 1) / 8
    iwidth = ilast - ifirst + 1
    rval = if (@ptr % 8).zero? then
      @buf[ifirst,iwidth]
    else
      lshift = @ptr % 8
      rshift = 8 - (@ptr % 8)
      a = @buf[ifirst,iwidth].unpack('C*')
      (0 ... len).map{|i|
        (0xFF & (a[i] << lshift)) | (a[i+1] >> rshift)
      }.pack('C*')
    end
    @ptr += width
    return nil if /^\xFF+$/n === rval
    # 通報式のいう CCITT IA5 とは ASCII だが、実際にはメキシコが
    # U+00D1 LATIN CAPITAL LETTER N WITH TILDE を入れてくるので救済。
    # 救済しすぎるのも考え物なので Windows-1252 にはしない
    rval.force_encoding(Encoding::ISO_8859_1)
  end

  def readstr desc
    return readstr1(desc[:width]) unless compressed?
    s0 = readstr1(desc[:width])
    n = getnum(@ptr, 6)
    @ptr += 6
    if n.zero? then
      return [s0] * nsubset
    end
    # カナダのSYNOPでは圧縮された文字列の参照値が通報式に定めるヌルでなく欠損値になっているので救済
    case s0
    when nil, /^\x00+$/ then
      rval = (0 ... nsubset).map{ readstr1(n * 8) }
      return rval
    else
      raise EBADF, "readstr: R0=#{s0.inspect} not nul"
    end
  end

  def decode_primary
    return if @props[:mastab]
    reftime = nil
    case @ed
    when 4 then
      @props[:mastab] = BUFRMsg::unpack1(@buf[@idsofs+3])
      @props[:ctr] = BUFRMsg::unpack2(@buf[@idsofs+4,2])
      @props[:subctr] = BUFRMsg::unpack2(@buf[@idsofs+6,2])
      @props[:upd] = BUFRMsg::unpack1(@buf[@idsofs+8])
      @props[:cat] = BUFRMsg::unpack1(@buf[@idsofs+10])
      @props[:subcat] = BUFRMsg::unpack1(@buf[@idsofs+11])
      @props[:masver] = BUFRMsg::unpack1(@buf[@idsofs+13])
      @props[:locver] = BUFRMsg::unpack1(@buf[@idsofs+14])
      reftime = [
        BUFRMsg::unpack2(@buf[@idsofs+15,2]),
        BUFRMsg::unpack1(@buf[@idsofs+17]),
        BUFRMsg::unpack1(@buf[@idsofs+18]),
        BUFRMsg::unpack1(@buf[@idsofs+19]),
        BUFRMsg::unpack1(@buf[@idsofs+20]),
        BUFRMsg::unpack1(@buf[@idsofs+21])
      ]
    when 3 then
      @props[:mastab] = BUFRMsg::unpack1(@buf[@idsofs+3])
      @props[:ctr] = BUFRMsg::unpack1(@buf[@idsofs+5])
      @props[:subctr] = BUFRMsg::unpack1(@buf[@idsofs+4])
      @props[:upd] = BUFRMsg::unpack1(@buf[@idsofs+6])
      @props[:cat] = BUFRMsg::unpack1(@buf[@idsofs+8])
      @props[:subcat] = BUFRMsg::unpack1(@buf[@idsofs+9])
      @props[:masver] = BUFRMsg::unpack1(@buf[@idsofs+10])
      @props[:locver] = BUFRMsg::unpack1(@buf[@idsofs+11])
      reftime = [
        BUFRMsg::unpack1(@buf[@idsofs+12]) + 2000,
        BUFRMsg::unpack1(@buf[@idsofs+13]),
        BUFRMsg::unpack1(@buf[@idsofs+14]),
        BUFRMsg::unpack1(@buf[@idsofs+15]),
        BUFRMsg::unpack1(@buf[@idsofs+16]),
        0
      ]
    when 2 then
      @props[:mastab] = BUFRMsg::unpack1(@buf[@idsofs+3])
      # code table 0 01 031
      @props[:ctr] = BUFRMsg::unpack2(@buf[@idsofs+4])
      @props[:upd] = BUFRMsg::unpack1(@buf[@idsofs+6])
      @props[:cat] = BUFRMsg::unpack1(@buf[@idsofs+8])
      @props[:subcat] = BUFRMsg::unpack1(@buf[@idsofs+9])
      @props[:masver] = BUFRMsg::unpack1(@buf[@idsofs+10])
      @props[:locver] = BUFRMsg::unpack1(@buf[@idsofs+11])
      reftime = [
        BUFRMsg::unpack1(@buf[@idsofs+12]) + 2000,
        BUFRMsg::unpack1(@buf[@idsofs+13]),
        BUFRMsg::unpack1(@buf[@idsofs+14]),
        BUFRMsg::unpack1(@buf[@idsofs+15]),
        BUFRMsg::unpack1(@buf[@idsofs+16]),
        0
      ]
    else # 現時点では build_sections で不明版数は排除される
      raise "BUG"
    end

    # 訂正報であるフラグ
    @props[:cflag] = if @props[:upd] > 0 then
        # Update Sequence Number が正ならば意識してやっていると信用する
        true
      elsif @props[:meta][:ahl]
        # 電文ヘッダ AHL が認識できるならばそれが訂正報であるかどうか
        if / CC.\b/ =~ @props[:meta][:ahl] then
          true
        else
          false
        end
      else
        # USN がゼロでも訂正のことはあるが、ヘッダがないならやむを得ず
        nil
      end

    @props[:nsubset] = BUFRMsg::unpack2(@buf[@ddsofs+4,2])
    ddsflags = BUFRMsg::unpack1(@buf[@ddsofs+6])
    @props[:obsp] = !(ddsflags & 0x80).zero?
    @props[:compress] = !(ddsflags & 0x40).zero?
    @props[:descs] = @buf[@ddsofs+7, @ddslen-7].unpack('n*').map{|d|
      f = d >> 14
      x = (d >> 8) & 0x3F
      y = d & 0xFF
      format('%01u%02u%03u', f, x, y)
    }.join(',')

    if [2000, 0, 0, 0, 0, 0] === reftime then
      reftime = Time.at(0).utc.to_a
    end
    begin
      @props[:reftime] = Time.gm(*reftime)
    rescue ArgumentError
      ep = @props[:descs].empty?
      raise EBADF, "Bad reftime #{reftime.inspect} ed=#{@ed} empty=#{ep}"
    end
  end

  def [] key
    @props[key]
  end

  def descs
    decode_primary
    @props[:descs]
  end

  def to_h
    decode_primary
    @props.dup
  end

  def ahl
    @props[:meta] ? @props[:meta][:ahl] : nil
  end

  def compressed?
    decode_primary
    @props[:compress]
  end

  def nsubset
    decode_primary
    @props[:nsubset]
  end

  def inspect
    require 'json'
    JSON.generate(to_h)
  end

  def show_ctr
    decode_primary
    p @props[:ctr]
  end

  # 各サブセットをデコードする前にデータ内容の日付を検査し、
  # 要すればいくらかビットをずらしてでも適正値が読める位置に移動する
  def ymdhack opts
    decode_primary
    # 日付記述子 004001/004002/004003 の位置が通知されなければ検査不能
    return unless opts[:ymd]
    # 圧縮電文はデータ位置がわからないため検査不能
    return if @props[:compress]
    # 日付検査1: 不正日付で落ちぬようTime型を構築せず22ビットで比較。
    # ほとんどの観測データは、BUFR第1節の参照時刻の日 (brt1)
    # またはその前日 (brt2) または欠損値 0x3F_FFFF となる。
    rt1 = @props[:reftime]
    brt1 = rt1.year << 10 | rt1.month << 6 | rt1.day
    rt2 = rt1 - 86400
    brt2 = rt2.year << 10 | rt2.month << 6 | rt2.day
    brtx = getnum(@ptr + opts[:ymd], 22)
    if brtx == brt1 or brtx == brt2 or brtx == 0x3F_FFFF
      return nil
    end
    # 日付検査2: 参照日と同じ月内のデータが来た場合
    if (brtx >> 10) == rt1.year and (0b1111 & (brtx >> 6)) == rt1.mon then
      # 日付検査2a: 参照日より前のデータは許容する
      if (1 ... rt1.day) === (0b111111 & brtx) then
	return nil
      end
      # 日付検査2b: 参照日が月初の場合に限り、データの同月末日を許容する
      #  これはエンコード誤りなので、参照日を破壊的訂正して翌月初とする
      if rt1.day == 1 then
        rt9 = Time.gm(rt1.year, rt1.mon, 0b111111 & brtx) + 86400
	if rt9.day == 1 then
	  @props[:reftime] = Time.gm(rt9.year, rt9.mon, 1,
	    rt1.hour, rt1.min, rt1.sec)
	  $stderr.puts "ymdhack: reftime corrected #{@props[:reftime]}"
	  return nil
	end
      end
    end
    # 日付検査3: 参照日の翌日（月末なら年月は繰り上がる）を許容する
    rt3 = rt1 + 86400
    if (brtx >> 10) == rt3.year and (0b1111 & (brtx >> 6)) == rt3.mon and
      (0b111111 & brtx) == rt3.day then
      $stderr.puts "ymdhack: tomorrow okay" if $DEBUG
      return nil
    end
    #
    # --- 日付検査失敗。ビットずれリカバリーモードに入る ---
    #
    $stderr.printf("ymdhack: mismatch %04u-%02u-%02u ids.rtime %s pos %u\n",
      brtx >> 10, 0b1111 & (brtx >> 6), 0b111111 & brtx,
      rt1.strftime('%Y-%m-%d'), @ptr)
    (-80 .. 10).each{|ofs|
      next if ofs.zero?
      xptr = @ptr + ofs
      brtx = getnum(xptr + opts[:ymd], 22)
      case brtx
      when brt1, brt2
        $stderr.puts "ymdhack: ptr #{xptr} <- #@ptr (shift #{xptr - @ptr})"
        @ptr = xptr
        return true
      end
    }
    if opts['001011'] then
      yptr = @ptr
      4.times{
        idx = @buf.index("\0\0\0\0", yptr / 8)
        if idx then
          $stderr.puts "ymdhack: 4NUL found at #{idx * 8} #{@ptr}"
          yptr = idx * 8 - opts['001011']
          (0).downto(-32){|ofs|
            xptr = yptr + ofs
            brtx = getnum(xptr + opts[:ymd], 22)
            case brtx
            when brt1, brt2
              $stderr.puts "ymdhack: ptr #{xptr} <- #@ptr (shift #{xptr - @ptr}) ofs #{ofs}"
              @ptr = xptr
              return true
            end
          }
        end
        yptr += opts['001011'] + 80
      }
    end
    if opts['001015'] then
      yptr = @ptr
      8.times{
        idx = [
          @buf.index("\x20\x20\x20\x20", yptr / 8),
          @buf.index("\x40\x40\x40\x40", yptr / 8),
          @buf.index("\x01\x01\x01\x01", yptr / 8),
          @buf.index("\x02\x02\x02\x02", yptr / 8),
          @buf.index("\x04\x04\x04\x04", yptr / 8),
          @buf.index("\x08\x08\x08\x08", yptr / 8),
          @buf.index("\x10\x10\x10\x10", yptr / 8)
          ].compact.min
        if idx then
          $stderr.puts "ymdhack: 4SPC found at #{idx * 8} #{@ptr}"
          yptr = idx * 8 - opts['001015']
          (0).downto(-132){|ofs|
            xptr = yptr + ofs
            brtx = getnum(xptr + opts[:ymd], 22)
            case brtx
            when brt1, brt2
              $stderr.puts "ymdhack: ptr #{xptr} <- #@ptr (shift #{xptr - @ptr}) ofs #{ofs}"
              @ptr = xptr
              return true
            end
          }
        end
        yptr += opts['001015'] + 80
      }
    end
    raise ENOSPC, "ymdhack - bit pat not found"
  end

end

=begin
任意の形式のファイル（ストリームでもまだいける）からBUFR電文を抽出する
=end

class BUFRScan

  def self.filescan fnam
    ahlsel = nil
    if /:AHL=/ === fnam then
      fnam = $`
      ahlsel = Regexp.new($')
    end
    File.open(fnam, 'r:BINARY'){|fp|
      fp.binmode
      BUFRScan.new(fp, fnam).scan{|msg|
        next if ahlsel and ahlsel !~ msg.ahl
        yield msg
      }
    }
  end

  def initialize io, fnam = '-'
    @io = io
    @buf = ""
    @ofs = 0
    @fnam = fnam
    @ahl = nil
  end

  def readmsg
    loop {
      idx = @buf.index('BUFR', @ofs)
      if idx.nil?
        @buf = @io.read(1024)
        return nil if @buf.nil?
        @ofs = 0
        next
      elsif idx > @ofs
        if /([A-Z]{4}(\d\d)? [A-Z]{4} \d{6}( [A-Z]{3})?)\r\r\n/ === @buf[@ofs,idx-@ofs] then
          @ahl = $1
        end
      end
      # check BUFR ... 7777 structure
      if @buf.bytesize - idx < 8 then
        buf2 = @io.read(1024)
        return nil if buf2.nil?
        @buf += buf2
      end
      msglen = BUFRMsg::unpack3(@buf[idx+4,3])
      if @buf.bytesize - idx < msglen then
        buf2 = @io.read(msglen - @buf.bytesize + idx)
        return nil if buf2.nil?
        @buf += buf2
      end
      endmark = @buf[idx + msglen - 4, 4]
      if endmark == '7777' then
        msg = BUFRMsg.new(@buf, idx, msglen, @fnam, @ahl)
        @ofs = idx + msglen
        return msg
      end
      @ofs += 4
    }
  end

  def scan
    loop {
      begin
        msg = readmsg
        return if msg.nil?
        yield msg
      rescue BUFRMsg::ENOSYS, BUFRMsg::EBADF => e
        STDERR.puts e.message + [@ahl].inspect
      end
    }
  end

end

if $0 == __FILE__
  action = :inspect
  ARGV.each{|fnam|
    case fnam
    when '-d' then
      action = :descs
    when /^-f(ctr)$/ then
      action = fnam.sub(/^-f/, 'show_').to_sym
    else
      BUFRScan.filescan(fnam){|msg|
        puts msg.send(action)
      }
    end
  }
end
