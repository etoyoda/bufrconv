#!/bin/bash
set -Ceuo pipefail

PATH=/bin:/usr/bin
TZ=UTC; export TZ

: ${nwp:=${HOME}/nwp-test}
: ${base:=${nwp}/p2}
: ${refhour:=$(date +'%Y-%m-%dT%HZ')}

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

ruby $nwp/bin/bufrsort LM:6,FN:zsort.txt z.curr.tar:AHL='^IS[MI]'
ruby $nwp/bin/sort2sfcmap.rb $basetime sfcplot$bt.html zsort.txt

rm -rf z*
cd $base
test ! -d ${refhour}-plot.bak || rm -rf ${refhour}-plot.bak
test ! -d ${refhour}-plot || mv -f ${refhour}-plot ${refhour}-plot.bak
mv $jobwk ${refhour}-plot
test -d $base/curr || mkdir $base/curr
ln -Tf ${base}/${refhour}-plot/sfcplot$bt.html ${base}/curr/sfcplot${hh}.html
exit 0
