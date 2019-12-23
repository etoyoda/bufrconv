#!/usr/bin/ruby

require 'gdbm'
require 'json'
require 'time'

class App

  def help
    $stderr.puts "usage: #$0 dbfile.gdbm maptime outfile.html"
    exit 16
  end

  def initialize argv
    @dbfile, maptime, outfile = argv
    raise if outfile.nil?
    @maptime = Time.parse(maptime).utc
  rescue => e
    $stderr.puts "#{e.class}: #{e.message}"
    help
  end

  def run
    pat = @maptime.strftime('^sfc/%Y-%m-%dT%HZ/')
    pattern = Regexp.new(pat)
      p pattern
    GDBM::open(@dbfile, GDBM::READER) {|db|
      db.each{|k, v|
        next unless pattern === k
	val = JSON.parse(v)
	p val
      }
    }
  end

end

App.new(ARGV).run
