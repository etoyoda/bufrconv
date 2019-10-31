  def peeknum ptr, width
    ifirst = ptr / 8
    raise ENOSPC, "peeknum #{ifirst} out of msg size #{$buf.bytesize}" if ifirst > $buf.bytesize
    ilast = (ptr + width) / 8
    iwidth = ilast - ifirst + 1
    ishift = 8 - ((ptr + width) % 8)
    imask = ((1 << width) - 1) << ishift
    ival = $buf[ifirst,iwidth].unpack('C*').inject{|r,i|(r<<8)|i}
    [iwidth, ishift, imask, ival]
  end

  def getnum ptr, width
    iwidth, ishift, imask, ival = peeknum(ptr, width)
    (imask & ival) >> ishift
  end

puts "=== FFFF ==="
$buf = ([0b11111111] * 64).pack('C*')

for width in 1..18
  for ptr in 0...16
    iwidth, ishift, imask, ival = peeknum(ptr, width)
    num = (imask & ival) >> ishift
    w = format('%%0%ub', width)
    printf("w=%-2u p=%-2u iw=%-2u is=%-3u num=#{w} im=#{w} iv=#{w}\n",
      width, ptr, iwidth, ishift, num, imask, ival)
  end
end

puts "=== WALTZ ==="
$buf = ([0b10010010, 0b01001001, 0b00100100] * 10).pack('C*')

for width in 1..18
  for ptr in 0...16
    iwidth, ishift, imask, ival = peeknum(ptr, width)
    num = (imask & ival) >> ishift
    w = format('%%0%ub', width)
    printf("w=%-2u p=%-2u iw=%-2u is=%-3u num=#{w} im=#{w} iv=#{w}\n",
      width, ptr, iwidth, ishift, num, imask, ival)
  end
end
