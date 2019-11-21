#!/bin/bash
set -Ceuo pipefail
export LANG=C
export TZ=UTC

notify(){
  set +x
  exec 2>&3
  tail batchlog.txt
  echo error exit
  cd ..
  test ! -d bufrval.bak || rm -rf bufrval.bak
  mv -f bufrval.tmp bufrval.bak
}
trap "notify" ERR

bc=$(dirname $0)
if [ X"$bc" = X"." ]; then
  bc=$(/bin/pwd)
fi

set `date --date=yesterday +'%Y %m %d %u'`
yy=$1
mm=$2
dd=$3
uu=$4

cd /nwp/p3/${yy}-${mm}
mkdir bufrval.tmp
cd bufrval.tmp

exec 3>&2
exec 2> batchlog.txt
set -x

tgz=/nwp/a0/${yy}-${mm}/obsbf-${yy}-${mm}-${dd}.tar.gz

date >&2

gzip -dc $tgz > obsbf-${yy}-${mm}-${dd}.tar
if ruby ${bc}/bufrdump.rb -d obsbf-${yy}-${mm}-${dd}.tar > /dev/null 2> dumperr.txt
then
  :
else
  tail -40 dumperr.txt
  false
fi

date >&2
rm -f obsbf-${yy}-${mm}-${dd}.tar

set +x
exec 2>&3
tar -czf - . > ../bufrval-${yy}-${mm}-${dd}.tar.gz
tail -300 dumperr.txt
cd ..
test ! -d bufrval.ok || rm -rf bufrval.ok
mv -f bufrval.tmp bufrval.ok
