for line in ARGF
  next unless /^0\d\d\d\d\d/ === line
  key = $&
  val = $'.sub(/ #\d\d\d.*/, '')
  case key
  when '001001' then ii = val.strip
  when '001002' then iii = val.strip
  when '014031' then
    val = val.strip
    puts [ii, iii, val].inspect unless val == 'nil'
  end
end
