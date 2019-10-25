#!/usr/bin/ruby

$VERBOSE = true if STDERR.tty?
def diag kwd, obj
 STDERR.puts kwd + ': ' + obj.inspect if $VERBOSE
end

class BUFRMsg

  def initialize buf, ofs, msglen, fnam = '-'
    @buf, @ofs, @msglen, @fnam = buf, ofs, msglen, fnam
  end

  def to_h
    { :fnam => @fnam, :ofs => @ofs, :msglen => @msglen }
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
      msglen = ("\0" + @buf[idx+4,3]).unpack('N').first
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
