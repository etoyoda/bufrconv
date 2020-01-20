#!/usr/bin/ruby

require 'time'

class App

  def help
    $stderr.puts "usage: #$0 [-opts] maptime outfile.(json|html) [zsort.txt ...]"
    exit 16
  end

  def initialize argv
    @flags = {}
    while /^-(\w+)(?:[:=](.*))?/ === argv.first
      argv.shift
      @flags[$1] = ($2 || true)
    end
    maptime = argv.shift
    help if maptime.nil?
    @outfile = argv.shift
    @files = argv
    @maptime = Time.parse(maptime).utc
    @level = 'sfc'
    @merge = {}
  rescue => e
    $stderr.puts "#{e.class}: #{e.message}"
    help
  end

  def htmlhead
    windbase = (@flags['WD'] ||
      'https://raw.githubusercontent.com/etoyoda/wxsymbols/master/img/')
    wxbase = (@flags['WX'] || @flags['WD'] ||
      'https://toyoda-eizi.net/wxsymbols/')
    <<HTML
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
<title>bufrsort #{@maptime} #{@level}</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.6.0/dist/leaflet.css"
  integrity="sha512-xwE/Az9zrjBIphAcBb3F6JVqxf46+CDLwfLMHloNu6KEQCAWi6HcDUbeOfBIptF7tcCzusKFjFw2yuvEpDL9wQ=="
  crossorigin=""/>
<style type="text/css">
.stn { width: 64px; height: 64px; }
.wb { width: 64px; height: 64px; position: absolute; top: 0; left: 0; }
.cl { width: 16px; height: 16px; position: absolute; top: 24px; left: 24px; }
.nw { font-size: 10px; line-height: 10px; text-shadow: 1px 1px 0 #FFF; 
  position: absolute; top: 20px; right: 38px; min-width: 5px; }
.ww { width: 20; height: 20; position: absolute; bottom: 11px; right: 32px; }
</style>
<script src="https://unpkg.com/leaflet@1.6.0/dist/leaflet.js"
   integrity="sha512-gZwIG9x3wUXg2hdXF6+rVkLF/0Vi9U8D2Ntg4Ga5I5BZpVkVxlJWbSQtXPSiUTtC0TjtGOmxa1AJPuV0CPthew=="
   crossorigin=""></script>
<script id="jsmain" type="text/javascript">
function init() {
  var tile1 = L.tileLayer('https://cyberjapandata.gsi.go.jp/xyz/pale/{z}/{x}/{y}.png', {
    attribution: '<a href="https://maps.gsi.go.jp/development/ichiran.html">地理院タイル</a>(淡色)',
    maxZoom: 14
  });
  var tile2 = L.tileLayer('https://cyberjapandata.gsi.go.jp/xyz/english/{z}/{x}/{y}.png', {
    attribution: '<a href="https://maps.gsi.go.jp/development/ichiran.html">地理院タイル</a>(標高)',
    maxZoom: 14
  });
  var basemaps = {
    "淡色地図": tile1,
    "標高": tile2
  };
  var decimal1 = new Intl.NumberFormat('en-US', { minimumFractionDigits: 1,
    maximumFractionDigits: 1 });
  var overlays = L.layerGroup([], {attribution: '<a href="https://github.com/OGCMetOceanDWG/WorldWeatherSymbols/">OGC</a>'});
  for (i in data) {
    obs = data[i]
    if (obs.La && obs.Lo) { 
      var dd = 'nil';
      var ff = 'nil';
      if (obs.d !== null) {
        dd = Math.floor((obs.d + 5) / 10);
	if (dd == 0) { dd = 36; }
      }
      if (obs.f !== null) {
	ff = Math.floor((obs.f + 1.25) / 2.5) * 5;
	if (ff > 100) {
	  ff = Math.floor((obs.f + 2.5) / 5) * 10;
	  if (ff > 150) { ff = 200; }
	}
	if ((ff == 0) && (obs.f > 0)) { ff = 5; }
	if (ff == 0) { dd = 0; }
      }
      var bn = 'd' + dd + 'f' + ff + '.png';
      var url = '#{windbase}' + bn;
      var nbn = 'nnil.png';
      if (obs.N !== null) {
        var n = Math.floor((obs.N + 6) / 12.5);
	if (n > 9) {
	  nbn = 'nauto.png';
	} else {
	  nbn = 'n' + n + '.png';
	}
      }
      var surl = '#{windbase}' + nbn;
      var ts = (typeof obs.T === 'number') ? Math.round(obs.T - 273.15) : '';
      var wx = '';
      if (typeof obs.w === 'number') {
        switch (obs.w) {
        case 0: case 1: case 2: case 3:
        case 100: case 101: case 102: case 103: case 508: case 509: case 510:
          break;
        default:
          wx = ('<img class="ww" src="#{wxbase}w' + obs.w + '.svg" alt="w' + obs.w + '" />');
        }
      }
      var ht = '<div class="stn"><img class="wb" src="' + url +
        '" /><img class="cl" src="' + surl +
        '" /><div class="nw">' + ts + '</div>' + wx + '</div>';
      var ic = L.divIcon({html: ht, className: 'stn', iconSize: [64, 64], iconAnchor: [32, 32]});
      var opt = {icon: ic, title: obs['@']};
      var pop = JSON.stringify(obs);
      L.marker([obs.La, obs.Lo], opt).bindPopup(pop).addTo(overlays);
    }
  }
  var mymap = L.map('mapid', {
    center: [35.0, 135.0],
    zoom: 5,
    layers: [tile1, overlays]
  });
  L.control.layers(basemaps, {"plot": overlays}).addTo(mymap);
}
</script>
<script id="jsdata" type="text/javascript">
var data =
HTML
  end

  def htmltail
    <<HTML
;
</script>
</head>
<body onLoad="init();">
<div id="mapid" style="width:100%;height:100%">map will be here</div>
</body>
</html>
HTML
  end

  def outjson io
    io.puts '['
    first = true
    @merge.each {|k, v|
      io.puts(v + ',')
    }
    io.puts '{"@":"dummy"}]'
  end

  def iopen
    if @files.empty? then
      yield $stdin
    else
      @files.each{|fnam|
	File.open(fnam, 'r:UTF-8') {|fp| yield fp }
      }
    end
  end

  def oopen
    case @outfile
    when nil, '-' then
      yield $stdout
    else
      File.open(@outfile, 'w:UTF-8') {|fp| yield fp }
    end
  end

  def run
    pat = @maptime.utc.strftime('^%Y-%m-%dT%H:%MZ/') + @level
    pattern = Regexp.new(pat)
    n = 0
    iopen() {|fp|
      fp.each_line{|line|
        next unless pattern === line
	n += 1
        k, v = line.chomp.split(/ /, 2)
	@merge[k] = v
      }
    }
    $stderr.puts "#{n} lines" if $VERBOSE
    oopen() {|ofp|
      ofp.write htmlhead if /\.html?$/ === @outfile
      outjson(ofp)
      ofp.write htmltail if /\.html?$/ === @outfile
    }
  end

end

$VERBOSE = true if $stderr.tty?
App.new(ARGV).run
