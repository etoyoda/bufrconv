#!/usr/bin/ruby

require 'time'

class App

  def help
    $stderr.puts "usage: #$0 [-opts] maptime level outfile.(json|html) [zsort.txt ...]"
    exit 16
  end

  def initialize argv
    @flags = {}
    while /^-(\w+)(?:[:=](.*))?/ === argv.first
      argv.shift
      @flags[$1] = ($2 || true)
    end
    maptime = argv.shift
    @level = argv.shift
    help if @level.nil?
    @outfile = argv.shift
    @files = argv
    @maptime = Time.parse(maptime).utc
    @merge = {}
  rescue => e
    $stderr.puts "#{e.class}: #{e.message}"
    help
  end

  def htmlhead
    bt = @maptime.strftime('%Y%m%d%H%M%S')
    windbase = (@flags['WD'] ||
      'https://raw.githubusercontent.com/etoyoda/wxsymbols/master/img/')
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
.ne { font-size: 10px; line-height: 10px; text-shadow: 1px 1px 0 #FFF; 
  position: absolute; top: 20px; left: 32px; text-aligh: left; }
.se { font-size: 10px; line-height: 10px; text-shadow: 1px 1px 0 #FFF; 
  position: absolute; bottom: 20px; left: 32px; text-aligh: left; }
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
  var tile3 = L.tileLayer('https://www.jma.go.jp/bosai/himawari/data/satimg/#{bt}/fd/#{bt}/B08/TBB/{z}/{x}/{y}.jpg', {
    attribution: '<a href="https://www.data.jma.go.jp/sat_info/himawari/satobs.html">気象庁</a>',
  });
  var tile4 = L.tileLayer('https://www.jma.go.jp/bosai/himawari/data/satimg/#{bt}/fd/#{bt}/B13/TBB/{z}/{x}/{y}.jpg', {
    attribution: '<a href="https://www.data.jma.go.jp/sat_info/himawari/satobs.html">気象庁</a>',
  });
  var tile5 = L.tileLayer('https://www.jma.go.jp/bosai/himawari/data/satimg/#{bt}/fd/#{bt}/SND/ETC/{z}/{x}/{y}.jpg', {
    attribution: '<a href="https://www.data.jma.go.jp/sat_info/himawari/satobs.html">気象庁</a>',
  });
  var basemaps = {
    "淡色地図": tile1,
    "標高": tile2,
    "ひまわり水蒸気": tile3,
    "ひまわり赤外": tile4,
    "ひまわり雲頂": tile5
  };
  var decimal1 = new Intl.NumberFormat('en-US', { minimumFractionDigits: 1,
    maximumFractionDigits: 1 });
  var overlays = L.layerGroup([]);
  for (i in data) {
    obs = data[i]
    if (obs.La && obs.Lo) { 
      var dd = 0;
      var ff = 0;
      if (obs.d && obs.f) {
        var dd = Math.floor((obs.d + 5) / 10);
	if (dd == 0) { dd = 36; }
	var ff = Math.floor((obs.f + 1.25) / 2.5) * 5;
	if (ff > 100) {
	  ff = Math.floor((obs.f + 2.5) / 5) * 10;
	  if (ff > 155) { ff = 200; }
	  if (ff > 135) { ff = 150; }
	}
	if (ff == 0) { dd = 0; }
      }
      var bn = 'd' + dd + 'f' + ff + '.png';
      var url = '#{windbase}' + bn;
      var ts = '';
      var ds = '';
      if (typeof obs.T === 'number') {
        ts = '<div class="ne">' + decimal1.format(obs.T - 273.15) + '</div>';
	if (typeof obs.Td == 'number') {
          ds = '<div class="se">' + decimal1.format(obs.T - obs.Td) + '</div>';
	}
      }
      var ht = '<div class="stn"><img class="wb" src="' + url +
        '" />' + ts + ds + '</div>';
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
  var cl = {"plot": overlays};
  var uHimdst = '#{@flags['HIMDST']}';
  if (uHimdst) {
    var himdst = L.imageOverlay(uHimdst, [[20,110],[50,150]], {attribution: 'Himawari'});
    cl[uHimdst] = himdst;
  }
  var uGpv1 = '#{@flags['GPV1']}';
  if (uGpv1) {
    var gpv1 = L.imageOverlay(uGpv1, [[-85.043,-179.3],[85.043,179.3]], {attribution: 'JMA', opacity:0.8});
    cl[uGpv1] = gpv1;
  }
  var uGpv2 = '#{@flags['GPV2']}';
  if (uGpv2) {
    var gpv2 = L.imageOverlay(uGpv2, [[-85.043,-179.3],[85.043,179.3]], {attribution: 'JMA', opacity:0.8});
    cl[uGpv2] = gpv2;
  }
  var uGpv3 = '#{@flags['GPV3']}';
  if (uGpv3) {
    var gpv3 = L.imageOverlay(uGpv3, [[-85.043,-179.3],[85.043,179.3]], {attribution: 'JMA', opacity:0.8});
    cl[uGpv3] = gpv3;
  }
  L.control.layers(basemaps, cl).addTo(mymap);
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
    pat = [@maptime.utc.strftime('^%Y-%m-%dT%H:%MZ'), @level, ''].join('/')
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
