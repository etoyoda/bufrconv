#!/bin/bash
set -Ceuo pipefail
export LANG=C
export TZ=UTC

cd $(dirname $0)
bc=$(/bin/pwd)

set `date --date=yesterday +'%Y %m %d %u'`
yy=$1
mm=$2
dd=$3
uu=$4

notify(){
  set +e
  exec 2>&3
  tail batchlog.txt
  echo error exit
  cd ..
  test ! -d bufrval.bak || rm -rf bufrval.bak
  mv -f bufrval.tmp bufrval.bak
}

mondir=/nwp/p3/${yy}-${mm}
test -d $mondir || mkdir $mondir
cd $mondir
mkdir bufrval.tmp
cd bufrval.tmp

exec 3>&2
trap "notify" ERR
exec 2> batchlog.txt
renice 18 $$ >/dev/null

tgz=/nwp/a0/${yy}-${mm}/obsbf-${yy}-${mm}-${dd}.tar.gz

date >&2

gzip -dc $tgz > obsbf-${yy}-${mm}-${dd}.tar
date >&2

if ruby ${bc}/statstn.rb obsbf-${yy}-${mm}-${dd}.tar > hdrstat.txt 2> dumperr.txt
then
  grep ': ' dumperr.txt || :
else
  tail -40 dumperr.txt
  false
fi
date >&2

if ruby ${bc}/bufr2synop.rb obsbf-${yy}-${mm}-${dd}.tar > /dev/null 2> synoperr.txt
then
  grep ' - ' synoperr.txt || :
else
  tail -40 synoperr.txt
  false
fi
date >&2

if ruby ${bc}/bufr2temp.rb obsbf-${yy}-${mm}-${dd}.tar > /dev/null 2> temperr.txt
then
  grep ' - ' temperr.txt || :
else
  tail -40 temperr.txt
  false
fi
date >&2

rm -f obsbf-${yy}-${mm}-${dd}.tar

set +e
exec 2>&3
tar -czf - hdrstat.txt batchlog.txt > ../bufrval-${yy}-${mm}-${dd}.tar.gz
cd ..
test ! -d bufrval.ok || rm -rf bufrval.ok
mv -f bufrval.tmp bufrval.ok
