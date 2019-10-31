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
    ahl = '-' unless ahl
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
      when 3
        BUFRMsg::unpack1(@buf[@idsofs + 7]) >> 7
      when 4
        BUFRMsg::unpack1(@buf[@idsofs + 9]) >> 7
      # fake --- not sure this is right, though works
      when 2
        0
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

  def readnum desc
    width, scale, refv = desc[:width], desc[:scale], desc[:refv]
    do_missing = !(/^031/ === desc[:fxy])
    if @ptr + width > @ptrmax
      raise ENOSPC, "end of msg reached #{@ptrmax} < #{@ptr} + #{width}"
    end
    iwidth, ishift, imask, ival = peeknum(@ptr, width)
    if $DEBUG then
      $stderr.puts({:readnum=>:start, :w=>width, :s=>scale, :r=>refv, :ptr=>@ptr,
      :byte=>@ptr/8, :bit=>@ptr%8, :iwidth=>iwidth, :ishift=>ishift}.inspect)
    end
    @ptr += width
    if ival & imask == imask and do_missing then
      if $DEBUG
        fmt = format('%%0%ub', iwidth * 8)
        $stderr.puts({:readnum=>:miss, :ival=>format(fmt, ival),
          :imask=>format(fmt, imask)}.inspect)
      end
      return nil
    end
    rval = ((imask & ival) >> ishift) + refv
    if $DEBUG then
      fmt = format('%%0%ub', iwidth * 8)
      $stderr.puts({:readnum=>:okay, :ival=>format(fmt, ival),
        :imask=>format(fmt, imask), :rval=>format(fmt, rval)}.inspect)
    end
    rval = rval.to_f * (10.0 ** -scale) unless scale.zero?
    rval
  end

  def readstr desc
    width = desc[:width]
    len = width / 8
    if @ptr + width > @ptrmax
      raise ENOSPC, "end of msg reached #{@ptrmax} < #{@ptr} + #{width}"
    end
    ifirst = @ptr / 8
    ilast = (@ptr + width - 1) / 8
    iwidth = ilast - ifirst + 1
    rval = if (@ptr % 8).zero? then
      @buf[ifirst,iwidth].force_encoding(Encoding::ASCII_8BIT)
    else
      lshift = @ptr % 8
      rshift = 8 - (@ptr % 8)
      a = @buf[ifirst,iwidth].unpack('C*')
      (0 ... len).map{|i|
        (0xFF & (a[i] << lshift)) | (a[i+1] >> rshift)
      }.pack('C*').force_encoding(Encoding::ASCII_8BIT)
    end
    @ptr += width
    rval
  end

  def decode_primary
    return if @props[:mastab]
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
      @props[:reftime] = Time.gm(
        BUFRMsg::unpack2(@buf[@idsofs+15,2]),
        BUFRMsg::unpack1(@buf[@idsofs+17]),
        BUFRMsg::unpack1(@buf[@idsofs+18]),
        BUFRMsg::unpack1(@buf[@idsofs+19]),
        BUFRMsg::unpack1(@buf[@idsofs+20]),
        BUFRMsg::unpack1(@buf[@idsofs+21])
      )
    when 3 then
      @props[:mastab] = BUFRMsg::unpack1(@buf[@idsofs+3])
      @props[:ctr] = BUFRMsg::unpack1(@buf[@idsofs+5])
      @props[:subctr] = BUFRMsg::unpack1(@buf[@idsofs+4])
      @props[:upd] = BUFRMsg::unpack1(@buf[@idsofs+6])
      @props[:cat] = BUFRMsg::unpack1(@buf[@idsofs+8])
      @props[:subcat] = BUFRMsg::unpack1(@buf[@idsofs+9])
      @props[:masver] = BUFRMsg::unpack1(@buf[@idsofs+10])
      @props[:locver] = BUFRMsg::unpack1(@buf[@idsofs+11])
      @props[:reftime] = Time.gm(
        BUFRMsg::unpack1(@buf[@idsofs+12]) + 2000,
        BUFRMsg::unpack1(@buf[@idsofs+13]),
        BUFRMsg::unpack1(@buf[@idsofs+14]),
        BUFRMsg::unpack1(@buf[@idsofs+15]),
        BUFRMsg::unpack1(@buf[@idsofs+16]),
        0
      )
    end
    @props[:nsubset] = BUFRMsg::unpack2(@buf[@ddsofs+4,2])
    ddsflags = BUFRMsg::unpack1(@buf[@ddsofs+6])
    @props[:obsp] = !(ddsflags & 0x80).zero?
    @props[:compress] = !(ddsflags & 0x40).zero?
    raise ENOSYS, "compressed file not supported" if @props[:compress]
    @props[:descs] = @buf[@ddsofs+7, @ddslen-7].unpack('n*').map{|d|
      f = d >> 14
      x = (d >> 8) & 0x3F
      y = d & 0xFF
      format('%01u%02u%03u', f, x, y)
    }.join(',')
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

  def inspect
    to_h.inspect
  end

  def ymdhack opts
    decode_primary
    return unless opts[:ymd]
    rt1 = @props[:reftime]
    brt1 = rt1.year << 10 | rt1.month << 6 | rt1.day
    rt2 = rt1 - 86400
    brt2 = rt2.year << 10 | rt2.month << 6 | rt2.day
    brtx = getnum(@ptr + opts[:ymd], 22)
    case brtx
    when brt1, brt2
      return nil
    end
    $stderr.printf("ymdhack: mismatch %04u-%02u-%02u ids.rtime %s\n",
      brtx >> 10, 0b1111 & (brtx >> 6), 0b111111 & brtx,
      rt1.strftime('%Y-%m-%d'))
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
    File.open(fnam, 'r:BINARY'){|fp|
      fp.binmode
      BUFRScan.new(fp, fnam).scan{|msg|
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
      rescue BUFRMsg::ENOSYS => e
        STDERR.puts e.message
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
    else
      BUFRScan.filescan(fnam){|msg|
        puts msg.send(action)
      }
    end
  }
end
