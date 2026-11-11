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

: --- prepare Himawari Dust Imagery ---
imgopt=
if test -f $nwp/bin/run-dst.sh
then
  if bash $nwp/bin/run-dst.sh
  then
    imgopt=-HIMDST:$(echo himdst*.png)
  fi
fi

: --- prepare Precip Nowcast ---
ymdhns=$(ruby -rtime -e 'puts(Time.parse(ARGV.first).utc.strftime("%Y%m%d%H%M%S"))' $basetime)
if test -d $nwp/p1/nowc/$ymdhns
then
  ln -f $nwp/p1/nowc/$ymdhns/surf_hrpns$ymdhns.png surf_hrpns${ymdhns}.png
  imgopt="${imgopt} -HRPNS:surf_hrpns${ymdhns}.png"
else
  logger --tag plot --id=$$ -p news.err -- "nowc $nwp/p1/nowc/$ymdhns missing"
fi

# base というのは誤りで gpv の valid time
gpvbase=$(ruby -rtime -e 'puts(Time.parse(ARGV.first).utc.strftime("%Y%m%dT%H%MZ"))' $basetime)
# GPV 探索 - 予報時間が短いもの優先、そのなかでjma があれば優先
gpvdir=''
ft=''
for ft in 6 9 12 15
do
  # こちらが gpv の basetime
  gpvtime=$(ruby -rtime -e 'puts((Time.parse(ARGV[0])-3600*ARGV[1].to_i).utc.strftime("%Y%m%dT%H"))' $basetime $ft)
  fft=$(printf 'f%03u' $ft)
  if test -f $nwp/p1/jmagrib/${gpvtime}Z/v${gpvbase}_${fft}_msl_Pmsl.png ; then
    gpvdir=$nwp/p1/jmagrib/${gpvtime}Z
    break
  elif test -f $nwp/p1/ukwmc/${gpvtime}Z/v${gpvbase}_${fft}_msl_Pmsl.png ; then
    gpvdir=$nwp/p1/ukwmc/${gpvtime}Z
    break
  fi
done
# 上記探索で GPV がみつかっていれば
if test -d "$gpvdir"
then
  logger --tag plot --id=$$ -p news.info -- "using ${gpvdir}"
  for ve in \
  msl_Pmsl z10_Pres z10_WD z10_WINDS z2_T sfc_RAIN \
  p50_Z p50_WINDS \
  p100_Z p100_WD p100_WINDS \
  p250_Z p250_T p250_WD p250_WINDS p250_rDIV \
  p500_Z p500_T p500_WD p500_WINDS p500_rVOR \
  p700_Z p700_RH p700_VVPa \
  p850_Z p850_T p850_papT p850_WINDS \
  p925_Z p925_papT p925_WD p925_WINDS
  do
    if test -f ${gpvdir}/v${gpvbase}_${fft}_${ve}.png ; then
      ln -f    ${gpvdir}/v${gpvbase}_${fft}_${ve}.png .
    fi
  done
  if test -f ${gpvdir}/gsm${gpvtime}.txt ; then
    ln    -f ${gpvdir}/gsm${gpvtime}.txt .
  fi
else
  logger --tag plot --id=$$ -p news.err -- "no gpv for ${gpvbase}"
fi

: --- prepare TAC decode ---
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
if test -f v${gpvbase}_${fft}_z10_WINDS.png ; then
  sfcopt="${sfcopt} -GPV1:v${gpvbase}_${fft}_z10_WINDS.png"
fi
if test -f v${gpvbase}_${fft}_p925_papT.png ; then
  sfcopt="${sfcopt} -GPV2:v${gpvbase}_${fft}_p925_papT.png"
fi
if test -f v${gpvbase}_${fft}_z10_Pres.png ; then
  sfcopt="${sfcopt} -GPV3:v${gpvbase}_${fft}_z10_Pres.png"
fi
if test -f v${gpvbase}_${fft}_msl_Pmsl.png ; then
  sfcopt="${sfcopt} -GPV4:v${gpvbase}_${fft}_msl_Pmsl.png"
fi
if test -f v${gpvbase}_${fft}_sfc_RAIN.png ; then
  sfcopt="${sfcopt} -GPV5:v${gpvbase}_${fft}_sfc_RAIN.png"
fi
if test -f v${gpvbase}_${fft}_z10_WD.png ; then
  sfcopt="${sfcopt} -GPV6:v${gpvbase}_${fft}_z10_WD.png"
fi
if test -f v${gpvbase}_${fft}_p700_RH.png ; then
  sfcopt="${sfcopt} -GPV7:v${gpvbase}_${fft}_p700_RH.png"
fi
ruby $nwp/bin/sort2sfcmap.rb $imgopt $sfcopt -WD:$wdbase $basetime sfcplot${bt}.html zmerge.txt
levels=''
case $hh in
00|12)
  levels='925 850 700 500 250 100 50'
  ;;
06|18)
  levels='925 850 700 500 250'
  ;;
*)
  levels='925 850 500'
;;
esac
for pres in $levels
do
  upropt=''
  case $pres in
  925|850)
    if test -f v${gpvbase}_${fft}_p${pres}_papT.png ; then
      upropt=-GPV1:v${gpvbase}_${fft}_p${pres}_papT.png
    fi
    if test -f v${gpvbase}_${fft}_p${pres}_WINDS.png ; then
      upropt="${upropt} -GPV2:v${gpvbase}_${fft}_p${pres}_WINDS.png"
    fi
    if test -f v${gpvbase}_${fft}_p${pres}_Z.png ; then
      upropt="${upropt} -GPV3:v${gpvbase}_${fft}_p${pres}_Z.png"
    fi
    if test -f v${gpvbase}_${fft}_p${pres}_WD.png ; then
      upropt="${upropt} -GPV4:v${gpvbase}_${fft}_p${pres}_WD.png"
    fi
    if test -f v${gpvbase}_${fft}_p${pres}_T.png ; then
      upropt="${upropt} -GPV5:v${gpvbase}_${fft}_p${pres}_T.png"
    fi
    ;;
  700)
    if test -f v${gpvbase}_${fft}_p${pres}_RH.png ; then
      upropt=-GPV1:v${gpvbase}_${fft}_p${pres}_RH.png
    fi
    if test -f v${gpvbase}_${fft}_p${pres}_Z.png ; then
      upropt="${upropt} -GPV2:v${gpvbase}_${fft}_p${pres}_Z.png"
    fi
    if test -f v${gpvbase}_${fft}_p${pres}_VVPa.png ; then
      upropt="${upropt} -GPV4:v${gpvbase}_${fft}_p${pres}_VVPa.png"
    fi
    ;;
  500)
    if test -f v${gpvbase}_${fft}_p${pres}_T.png ; then
      upropt="${upropt} -GPV1:v${gpvbase}_${fft}_p${pres}_T.png"
    fi
    if test -f v${gpvbase}_${fft}_p${pres}_Z.png ; then
      upropt="${upropt} -GPV2:v${gpvbase}_${fft}_p${pres}_Z.png"
    fi
    if test -f v${gpvbase}_${fft}_p${pres}_rVOR.png ; then
      upropt="${upropt} -GPV4:v${gpvbase}_${fft}_p${pres}_rVOR.png"
    fi
    if test -f v${gpvbase}_${fft}_p700_RH.png ; then
      upropt="${upropt} -GPV5:v${gpvbase}_${fft}_p700_RH.png"
    fi
    ;;
  50|100|250)
    if test -f v${gpvbase}_${fft}_p${pres}_WINDS.png ; then
      upropt="${upropt} -GPV1:v${gpvbase}_${fft}_p${pres}_WINDS.png"
    fi
    if test -f v${gpvbase}_${fft}_p${pres}_Z.png ; then
      upropt="${upropt} -GPV2:v${gpvbase}_${fft}_p${pres}_Z.png"
    fi
    if test -f v${gpvbase}_${fft}_p${pres}_rDIV.png ; then
      upropt="${upropt} -GPV4:v${gpvbase}_${fft}_p${pres}_rDIV.png"
    fi
    if test -f v${gpvbase}_${fft}_p${pres}_T.png ; then
      upropt="${upropt} -GPV5:v${gpvbase}_${fft}_p${pres}_T.png"
    fi
    if test -f v${gpvbase}_${fft}_p${pres}_WD.png ; then
      upropt="${upropt} -GPV6:v${gpvbase}_${fft}_p${pres}_WD.png"
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
