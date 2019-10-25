#!/usr/bin/ruby

$VERBOSE = true if STDERR.tty?
def diag kwd, obj
 STDERR.puts kwd + ': ' + obj.inspect if $VERBOSE
end

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

  def initialize buf, ofs, msglen, fnam = '-'
    @buf, @ofs, @msglen, @fnam = buf, ofs, msglen, fnam
    @ed = @buf[ofs+7].unpack('C').first
    @props = { :fnam => @fnam, :ofs => @ofs, :msglen => @msglen, :ed => @ed }
    build_sections
  end

  def build_sections
    #
    # building section structure with size validation
    #
    esofs = @ofs + @msglen - 4
    raise EBADF, "Edition #{@ed} != 4" unless 4 == @ed
    @idsofs = @ofs + 8
    @idslen = BUFRMsg::unpack3(@buf[@idsofs, 3])
    if @buf[@idsofs + 9].unpack('C').first != 0 then
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
  end

  def decode_ids
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
  end

  def to_h
    decode_ids
    @props.dup
  end

  def inspect
    to_h.inspect
  end

end

class BUFRScan

  def initialize io, fnam = '-'
    @io = io
    @buf = ""
    @ofs = 0
    @fnam = fnam
  end

  def readmsg
    loop {
      idx = @buf.index('BUFR', @ofs)
      if idx.nil?
        @buf = @io.read(1024)
        return nil if @buf.nil?
        @ofs = 0
        next
      end
      # check BUFR ... 7777 structure
      msglen = BUFRMsg::unpack3(@buf[idx+4,3])
      if @buf.bytesize - idx < msglen then
        @buf += @io.read(msglen - @buf.bytesize + idx)
      end
      endmark = @buf[idx + msglen - 4, 4]
      if endmark == '7777' then
        msg = BUFRMsg.new(@buf, idx, msglen, @fnam)
        @ofs = idx + msglen
        return msg
      end
      @ofs += 4
    }
  end

  def scan
    while msg = readmsg
      yield msg
    end
  end

end

if $0 == __FILE__
  ARGV.each{|fnam|
    File.open(fnam, 'r:BINARY'){|fp|
      fp.binmode
      BUFRScan.new(fp, fnam).scan{|msg|
        p msg
      }
    }
  }
end
