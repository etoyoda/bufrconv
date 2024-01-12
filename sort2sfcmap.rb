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
    bt = @maptime.strftime('%Y%m%d%H%M%S')
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
.cd { width: 16px; height: 16px; position: absolute; top: 24px; left: 24px; }
.nw { font-size: 10px; line-height: 10px; text-shadow: 1px 1px 0 #FFF; 
  position: absolute; top: 20px; right: 38px; min-width: 5px; }
.ww { width: 20; height: 20; position: absolute; bottom: 11px; right: 32px; }
.cl { width: 14; height: 14; position: absolute; top: 38px;    left: 30px; }
.cm { width: 14; height: 14; position: absolute; bottom: 36px; left: 30px; }
.ch { width: 14; height: 14; position: absolute; bottom: 48px; left: 30px; }
</style>
<script src="https://unpkg.com/leaflet@1.6.0/dist/leaflet.js"
   integrity="sha512-gZwIG9x3wUXg2hdXF6+rVkLF/0Vi9U8D2Ntg4Ga5I5BZpVkVxlJWbSQtXPSiUTtC0TjtGOmxa1AJPuV0CPthew=="
   crossorigin=""></script>
<script id="jsmain" type="text/javascript">
function plot(lgplot, obs) {
  const wxbase = '#{wxbase}';
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
      if (obs.N === null) {
        if (!('ix' in obs)) {
          nbn = 'n9.png';
        } else if (obs.ix == 0) {
          nbn = 'nauto.png';
        }
      } else {
        var n = Math.floor((obs.N + 6) / 12.5);
	nbn = 'n' + n + '.png';
      }
      var surl = '#{windbase}' + nbn;
      var ts = '';
      if (typeof obs.T === 'number') {
        ts = '<div class="nw">' + Math.round(obs.T - 273.15) + '</div>';
      }
      var wx = '';
      if (typeof obs.w === 'number') {
        switch (obs.w) {
        case 0: case 1: case 2: case 3:
        case 100: case 101: case 102: case 103: case 508: case 509: case 510:
          break;
        default:
          wx = ('<img class="ww" src="' + wxbase + 'w' + obs.w + '.svg" alt="w' + obs.w + '" />');
        }
      }
      var cl = '';
      if (obs.CL) { cl = '<img class="cl" src="' + wxbase + 'cl' + obs.CL + '.svg" />'; }
      var cm = '';
      if (obs.CM) { cm = '<img class="cm" src="' + wxbase + 'cm' + obs.CM + '.svg" />'; }
      var ch = '';
      if (obs.CH) { ch = '<img class="ch" src="' + wxbase + 'ch' + obs.CH + '.svg" />'; }
      var ht = '<div class="stn"><img class="wb" src="' + url +
        '" /><img class="cd" src="' + surl +
        '" />' + ts + wx + cl + cm + ch + '</div>';
      var ic = L.divIcon({html: ht, className: 'stn', iconSize: [64, 64], iconAnchor: [32, 32]});
      var opt = {icon: ic, title: obs['@']};
      var pop = '<table border=1>';
      for (const field in obs) {
        pop += '<tr><th>' + field + '</th><td>' + obs[field] + '</td></tr>';
      }
      pop += '</table>';
      L.marker([obs.La, obs.Lo], opt).bindPopup(pop).addTo(lgplot);
    }
}
function init() {
  var tile1 = L.tileLayer('https://cyberjapandata.gsi.go.jp/xyz/pale/{z}/{x}/{y}.png', {
    attribution: '<a href="https://maps.gsi.go.jp/development/ichiran.html">地理院タイル</a>(淡色)',
    maxZoom: 14
  });
  var tile2 = L.tileLayer('https://cyberjapandata.gsi.go.jp/xyz/english/{z}/{x}/{y}.png', {
    attribution: '<a href="https://maps.gsi.go.jp/development/ichiran.html">地理院タイル</a>(標高)',
    maxZoom: 14
  });
  var tile3 = L.tileLayer('https://www.jma.go.jp/bosai/himawari/data/satimg/#{bt}/fd/#{bt}/REP/ETC/{z}/{x}/{y}.jpg', {
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
    "ひまわり色": tile3,
    "ひまわり赤外": tile4,
    "ひまわり雲頂": tile5
  };
  var decimal1 = new Intl.NumberFormat('en-US', { minimumFractionDigits: 1,
    maximumFractionDigits: 1 });
  var lgplot = L.layerGroup([], {attribution: '<a href="https://github.com/OGCMetOceanDWG/WorldWeatherSymbols/">OGC</a>'});
  var mymap = L.map('mapid', {
    center: [35.0, 135.0],
    zoom: 5,
    layers: [tile1, lgplot]
  });
  var cl = {"plot": lgplot};
  var uHimdst = '#{@flags['HIMDST']}';
  var uHrpns = '#{@flags['HRPNS']}';
  if (uHimdst) {
    var himdst = L.imageOverlay(uHimdst, [[20,110],[50,150]], {attribution: 'Himawari'});
    cl[uHimdst] = himdst;
  }
  var uGpv1 = '#{@flags['GPV1']}';
  if (uGpv1) {
    var gpv1 = L.imageOverlay(uGpv1, [[-85.043,-179.3],[85.043,179.3]], {attribution: 'JMA', opacity:0.8});
    mymap.addLayer(gpv1);
    cl[uGpv1] = gpv1;
  }
  var uGpv2 = '#{@flags['GPV2']}';
  if (uGpv2) {
    var gpv2 = L.imageOverlay(uGpv2, [[-85.043,-179.3],[85.043,179.3]], {attribution: 'JMA', opacity:0.8});
    mymap.addLayer(gpv2);
    cl[uGpv2] = gpv2;
  }
  var uGpv3 = '#{@flags['GPV3']}';
  if (uGpv3) {
    var gpv3 = L.imageOverlay(uGpv3, [[-85.043,-179.3],[85.043,179.3]], {attribution: 'JMA', opacity:0.8});
    mymap.addLayer(gpv3);
    cl[uGpv3] = gpv3;
  }
  var uGpv4 = '#{@flags['GPV4']}';
  if (uGpv4) {
    var gpv4 = L.imageOverlay(uGpv4, [[-85.043,-179.3],[85.043,179.3]], {attribution: 'JMA', opacity:0.8});
    cl[uGpv4] = gpv4;
  }
  var uGpv5 = '#{@flags['GPV5']}';
  if (uGpv5) {
    var gpv5 = L.imageOverlay(uGpv5, [[-85.043,-179.3],[85.043,179.3]], {attribution: 'JMA', opacity:0.8});
    cl[uGpv5] = gpv5;
  }
  var uGpv6 = '#{@flags['GPV6']}';
  if (uGpv6) {
    var gpv6 = L.imageOverlay(uGpv6, [[-85.043,-179.3],[85.043,179.3]], {attribution: 'JMA', opacity:0.8});
    cl[uGpv6] = gpv6;
  }
  if (uHrpns) {
    var hrpns = L.imageOverlay(uHrpns, [[21.942986,118.124957],[48.922485,151.874957]], {attribution: 'JMA HRPNS'});
    cl[uHrpns] = hrpns;
  }
  L.control.layers(basemaps, cl).addTo(mymap);
  for (i in data) {
    plot(lgplot, data[i]);
  }
  mymap.on('keydown', function(ev){
    if (ev.originalEvent.code == 'KeyU') {
      mymap.panTo([50, 30]);
    } else if (ev.originalEvent.code == 'KeyJ') {
      mymap.panTo([35, 135]);
    }
  });
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
