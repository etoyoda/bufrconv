#!/usr/bin/ruby

puts "#!/usr/bin/ruby"

main = ARGV.shift
ARGV.each{|arg|
  puts "# 1 #{arg.inspect}"
  File.open(arg, 'r'){|ifp|
    kill = false
    ifp.each_line{|line|
      if kill then
        kill = false if /^end/ === line
      elsif /^if (__FILE__ == \$0|\$0 == __FILE__)/ === line
        kill = true
      elsif /##del/ === line then
      else
        puts line
      end
    }
  }
}
puts "# 1 #{main.inspect}"
File.open(main, 'r'){|fp|
  fp.each_line{|line|
    next if /##del/ === line
    puts line
  }
}
