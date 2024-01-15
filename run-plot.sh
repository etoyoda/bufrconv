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
gpvtime=$(ruby -rtime -e 'puts((Time.parse(ARGV.first)-3600*6).utc.strftime("%Y%m%dT%H"))' $basetime)
gpvbase=$(ruby -rtime -e 'puts(Time.parse(ARGV.first).utc.strftime("%Y%m%dT%H%MZ"))' $basetime)
if test -d $nwp/p1/jmagrib/${gpvtime}Z
then
  for ve in msl_Pmsl p100_WINDS p200_Z p200_WINDS p250_rDIV p300_Z p300_WINDS p500_Z p500_T p500_rVOR p700_RH p700_VVPa p850_Z p850_papT p850_WINDS p925_Z p925_papT p925_WD sfc_RAIN z10_WD z2_T p925_WINDS z10_WINDS p500_WINDS p100_WD p200_WD p300_WD p500_WD
  do
    if test -f $nwp/p1/jmagrib/${gpvtime}Z/v${gpvbase}_f006_${ve}.png ; then
      ln -f    $nwp/p1/jmagrib/${gpvtime}Z/v${gpvbase}_f006_${ve}.png .
    fi
  done
  if test -f $nwp/p1/jmagrib/${gpvtime}Z/gsm${gpvtime}.txt ; then
    ln    -f $nwp/p1/jmagrib/${gpvtime}Z/gsm${gpvtime}.txt .
  fi
fi

if test -f $nwp/bin/run-detac.sh
then
  bash $nwp/bin/run-detac.sh || :
fi

ruby $nwp/bin/bufrsort LM:6,FN:zsort.txt z.curr.tar:AHL="$ahl" > bufrsort.log 2>&1
obsfiles=zsort.txt
if test -f zloctac.txt ; then
  obsfiles="$obsfiles zloctac.txt"
fi
if test -f gsm${gpvtime}.txt ; then
  obsfiles="$obsfiles gsm${gpvtime}.txt"
fi
ruby $nwp/bin/distillobs.rb $obsfiles >| zmerge.txt
ln zmerge.txt sfc${bt}.txt
sfcopt=''
if test -f v${gpvbase}_f006_z10_WINDS.png ; then
  sfcopt="${sfcopt} -GPV1:v${gpvbase}_f006_z10_WINDS.png"
fi
if test -f v${gpvbase}_f006_p700_RH.png ; then
  sfcopt="${sfcopt} -GPV2:v${gpvbase}_f006_p700_RH.png"
fi
if test -f v${gpvbase}_f006_msl_Pmsl.png ; then
  sfcopt="${sfcopt} -GPV3:v${gpvbase}_f006_msl_Pmsl.png"
fi
if test -f v${gpvbase}_f006_sfc_RAIN.png ; then
  sfcopt="${sfcopt} -GPV4:v${gpvbase}_f006_sfc_RAIN.png"
fi
if test -f v${gpvbase}_f006_z10_WD.png ; then
  sfcopt="${sfcopt} -GPV5:v${gpvbase}_f006_z10_WD.png"
fi
if test -f v${gpvbase}_f006_z2_T.png ; then
  sfcopt="${sfcopt} -GPV6:v${gpvbase}_f006_z2_T.png"
fi
ruby $nwp/bin/sort2sfcmap.rb $imgopt $sfcopt -WD:$wdbase $basetime sfcplot${bt}.html zmerge.txt
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
    if test -f v${gpvbase}_f006_p${pres}_WINDS.png ; then
      upropt="${upropt} -GPV2:v${gpvbase}_f006_p${pres}_WINDS.png"
    fi
    if test -f v${gpvbase}_f006_p${pres}_Z.png ; then
      upropt="${upropt} -GPV3:v${gpvbase}_f006_p${pres}_Z.png"
    fi
    if test -f v${gpvbase}_f006_p${pres}_WD.png ; then
      upropt="${upropt} -GPV4:v${gpvbase}_f006_p${pres}_WD.png"
    fi
    if test -f v${gpvbase}_f006_p${pres}_T.png ; then
      upropt="${upropt} -GPV5:v${gpvbase}_f006_p${pres}_T.png"
    fi
    ;;
  700)
    if test -f v${gpvbase}_f006_p${pres}_RH.png ; then
      upropt=-GPV1:v${gpvbase}_f006_p${pres}_RH.png
    fi
    if test -f v${gpvbase}_f006_p${pres}_VVPa.png ; then
      upropt="${upropt} -GPV2:v${gpvbase}_f006_p${pres}_VVPa.png"
    fi
    ;;
  100|200|300|500)
    if test -f v${gpvbase}_f006_p${pres}_WINDS.png ; then
      upropt="-GPV1:v${gpvbase}_f006_p${pres}_WINDS.png"
    fi
    if test -f v${gpvbase}_f006_p${pres}_T.png ; then
      upropt="${upropt} -GPV2:v${gpvbase}_f006_p${pres}_T.png"
    elif test -f v${gpvbase}_f006_p${pres}_WD.png ; then
      upropt="${upropt} -GPV2:v${gpvbase}_f006_p${pres}_WD.png"
    fi
    if test -f v${gpvbase}_f006_p${pres}_Z.png ; then
      upropt="${upropt} -GPV3:v${gpvbase}_f006_p${pres}_Z.png"
    fi
    if test -f v${gpvbase}_f006_p${pres}_rVOR.png ; then
      upropt="${upropt} -GPV4:v${gpvbase}_f006_p${pres}_rVOR.png"
    fi
    if test -f v${gpvbase}_f006_p250_rDIV.png ; then
      upropt="${upropt} -GPV5:v${gpvbase}_f006_p250_rDIV.png"
    fi
    if test -f v${gpvbase}_f006_p700_RH.png ; then
      upropt="${upropt} -GPV6:v${gpvbase}_f006_p700_RH.png"
    fi
    ;;
  esac
  ruby $nwp/bin/sort2uprmap.rb $imgopt $upropt -WD:$wdbase $basetime \
    p${pres} p${pres}plot${bt}.html zmerge.txt
done


rm -rf z*
cd $base
test ! -d ${bt}-plot || rm -rf ${bt}-plot
mv $jobwk ${bt}-plot
rm -f curr
ln -s ${bt}-plot curr

exit 0
