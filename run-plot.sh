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

basetime=$(ruby -rtime -e 'puts(Time.at((Time.parse(ARGV.first.sub(/Z/,":00:00Z")).to_i / (6 * 3600)) * 6 * 3600).utc.strftime("%Y-%m-%dT%H:%M:%SZ"))' $refhour)
bt=$(ruby -rtime -e 'puts(Time.parse(ARGV.first).utc.strftime("%Y-%m-%dT%HZ"))' $basetime)
hh=$(ruby -rtime -e 'puts(Time.parse(ARGV.first).utc.strftime("%H"))' $basetime)

ln -Tfs $nwp/p0/incomplete/obsbf-2*.tar z.curr.tar

ahl='^I(SM|SI)'
case $hh in
00|12)
  ahl='^I(SM|SI|US|UK)'
;;
esac

ruby $nwp/bin/bufrsort LM:6,FN:zsort.txt z.curr.tar:AHL="$ahl"
ruby $nwp/bin/sort2sfcmap.rb -WD:$wdbase $basetime sfcplot${bt}.html zsort.txt
case $hh in
00|12)
  for pres in 925 850 700 500 300 200 100 50
  do
    ruby $nwp/bin/sort2uprmap.rb -WD:$wdbase $basetime p${pres} \
      p${pres}plot${bt}.html zsort.txt
  done
;;
esac


rm -rf z*
cd $base
test ! -d ${refhour}-plot || rm -rf ${refhour}-plot
mv $jobwk ${refhour}-plot
test -d $base/curr || mkdir $base/curr
ln -Tf ${base}/${refhour}-plot/sfcplot${bt}.html ${base}/curr/sfcplot${hh}.html
for pres in 925 850 700 500 300 200 100 50
do
  if test -f ${base}/${refhour}-plot/p${pres}plot${bt}.html
  then
    ln -Tf ${base}/${refhour}-plot/p${pres}plot${bt}.html \
      ${base}/curr/p${pres}plot${hh}.html
  fi
done
exit 0
