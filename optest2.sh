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


gzip -dc $tgz > obsbf-${yy}-${mm}-${dd}.tar

if ruby ${bc}/statstn.rb obsbf-${yy}-${mm}-${dd}.tar > hdrstat.txt 2> dumperr.txt
then
  :
else
  tail -40 dumperr.txt
  false
fi
grep ': ' dumperr.txt >&2 || :

if ruby ${bc}/bufr2synop.rb obsbf-${yy}-${mm}-${dd}.tar > /dev/null 2> synoperr.txt
then
  :
else
  tail -40 synoperr.txt
  false
fi
#QUICK AND DIRTY MASK OF UNSUPPORTED FEATURES
sed -ne '/ 003002/d; / 203014/d; / - /p' synoperr.txt >&2 || :
#WAS: grep ' - ' synoperr.txt >&2 || :

if ruby ${bc}/bufr2temp.rb obsbf-${yy}-${mm}-${dd}.tar > /dev/null 2> temperr.txt
then
  :
else
  tail -40 temperr.txt
  false
fi
#QUICK AND DIRTY MASK OF UNSUPPORTED FEATURES
sed -ne '/ 207001/d; / - /p' temperr.txt >&2 || :
#WAS: grep ' - ' synoperr.txt >&2 || :

rm -f obsbf-${yy}-${mm}-${dd}.tar

set +e
exec 2>&3
trap -- '' ERR
tar -czf - hdrstat.txt batchlog.txt > ../bufrval-${yy}-${mm}-${dd}.tar.gz
if test -s batchlog.txt ; then
  head -300 batchlog.txt
  if addr=`cat ${HOME}/.mailto-pub` ; then
    head -300 batchlog.txt | mail --subject bufrval-${yy}-${mm}-${dd} $addr
  fi
else
  echo "bufrval-${yy}-${mm}-${dd}.tar.gz w/empty log"
fi
cd ..
test ! -d bufrval.ok || rm -rf bufrval.ok
mv -f bufrval.tmp bufrval.ok
