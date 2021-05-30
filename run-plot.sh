#!/bin/bash
set -Ceuo pipefail

PATH=/bin:/usr/bin
TZ=UTC; export TZ

: ${nwp:=${HOME}/nwp-test}
: ${base:=${nwp}/p2}
: ${refhour:=$(date +'%Y-%m-%dT%HZ')}
: ${wdbase:='https://raw.githubusercontent.com/etoyoda/wxsymbols/master/img/'}

cd $base
if test -f stop ; then
  logger --tag plot --id=$$ -p news.err -- "suspended - remove ${base}/stop"
  false
fi

jobwk=${base}/wk.${refhour}-plot.$$
mkdir $jobwk
cd $jobwk

: 10800 == 3600 x 3
basetime=$(ruby -rtime -e 'puts(Time.at(((Time.parse(ARGV.first.sub(/Z/,":00:00Z")).to_i - 3600) / 10800) * 10800).utc.strftime("%Y-%m-%dT%H:%M:%SZ"))' $refhour)
export basetime
bt=$(ruby -rtime -e 'puts(Time.parse(ARGV.first).utc.strftime("%Y-%m-%dT%HZ"))' $basetime)
hh=$(ruby -rtime -e 'puts(Time.parse(ARGV.first).utc.strftime("%H"))' $basetime)

ln -Tfs $nwp/p0/incomplete/obsbf-2*.tar z.curr.tar

ahl='^I(SM|SI|SN|SS)'
case $hh in
00|06|12|18)
  ahl='^I(SM|SI|SN|SS|UP|UJ|US|UK)'
;;
*)
  ahl='^I(SM|SI|SN|SS|UP|UJ|UK)'
;;
esac

imgopt=
if test -f $nwp/bin/run-dst.sh
then
  if bash $nwp/bin/run-dst.sh
  then
    imgopt=-HIMDST:$(echo himdst*.png)
  fi
fi
ymdhns=$(ruby -rtime -e 'puts(Time.parse(ARGV.first).utc.strftime("%Y%m%d%H%M%S"))' $basetime)
if test -d $nwp/p1/nowc/$ymdhns
then
  ln -f $nwp/p1/nowc/$ymdhns/surf_hrpns$ymdhns.png surf_hrpns${ymdhns}.png
  imgopt="${imgopt} -HRPNS:surf_hrpns${ymdhns}.png"
else
  logger --tag plot --id=$$ -p news.err -- "nowc $nwp/p1/nowc/$ymdhns missing"
fi
gpvtime=$(ruby -rtime -e 'puts((Time.parse(ARGV.first)-3600*6).utc.strftime("%Y%m%dT%HZ"))' $basetime)
gpvbase=$(ruby -rtime -e 'puts(Time.parse(ARGV.first).utc.strftime("%Y%m%dT%H%MZ"))' $basetime)
if test -d $nwp/p1/jmagrib/${gpvtime}
then
  for ve in msl_Pmsl p300_Z p500_Z p850_papT p925_papT sfc_RAIN
  do
    ln -f $nwp/p1/jmagrib/${gpvtime}/v${gpvbase}_f006_${ve}.png .
  done
fi

ruby $nwp/bin/bufrsort LM:6,FN:zsort.txt z.curr.tar:AHL="$ahl" > bufrsort.log 2>&1
ln zsort.txt sfc${bt}.txt
sfcopt=''
if test -f v${gpvbase}_f006_msl_Pmsl.png ; then
  sfcopt=-GPV1:v${gpvbase}_f006_msl_Pmsl.png
fi
if test -f v${gpvbase}_f006_sfc_RAIN.png ; then
  sfcopt="${sfcopt} -GPV2:v${gpvbase}_f006_sfc_RAIN.png"
fi
ruby $nwp/bin/sort2sfcmap.rb $imgopt $sfcopt -WD:$wdbase $basetime sfcplot${bt}.html zsort.txt
levels=''
case $hh in
00|12)
  levels='925 850 700 500 300 200 100 50'
  ;;
06|18)
  levels='925 850 700 500 300'
  ;;
*)
  levels='925 850'
;;
esac
for pres in $levels
do
  upropt=''
  case $pres in
  925|850)
    if test -f v${gpvbase}_f006_p${pres}_papT.png ; then
      upropt=-GPV1:v${gpvbase}_f006_p${pres}_papT.png
    fi
    ;;
  300|500)
    if test -f v${gpvbase}_f006_p${pres}_Z.png ; then
      upropt=-GPV1:v${gpvbase}_f006_p${pres}_Z.png
    fi
    ;;
  esac
  ruby $nwp/bin/sort2uprmap.rb $imgopt $upropt -WD:$wdbase $basetime \
    p${pres} p${pres}plot${bt}.html zsort.txt
done


rm -rf z*
cd $base
test ! -d ${bt}-plot || rm -rf ${bt}-plot
mv $jobwk ${bt}-plot
test -d $base/curr || mkdir $base/curr
for plane in sfc p925 p850 p700 p500 p300 p200 p100 p50
do
  if test -f ${base}/${bt}-plot/${plane}plot${bt}.html
  then
    ln -Tf ${base}/${bt}-plot/${plane}plot${bt}.html \
      ${base}/curr/${plane}plot${hh}.html
  fi
done
exit 0
