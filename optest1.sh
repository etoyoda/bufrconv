#!/bin/sh
LANG=C
TZ=UTC
export TZ

cd `dirname $0`

: ${FORCEDATE:=now}

set `date --date=$FORCEDATE +'%Y %m %d %H %M'`
yy=$1
mm=$2
dd=$3
hh=$4
nn=$5
set `date --date=yesterday +'%Y %m %d'`
y1=$1
m1=$2
d1=$3

LOGFILE=LOG.${hh}${nn}

exec 3>&2
exec 2> ${LOGFILE}
set -x

test ! -f BUCKET || rm -f BUCKET
tar=/nwp/p0/${yy}-${mm}-${dd}.new/obsbf-${yy}-${mm}-${dd}.tar
tar1=/nwp/p0/${y1}-${m1}-${d1}/obsbf-${y1}-${m1}-${d1}.tar
if test 00 = ${hh} ; then
  test -f $tar1 || sleep 5
  test -f $tar1 || sleep 10
  test -f $tar1 || sleep 15
  if test -f $tar -a -f $tar1 ; then
    cat $tar $tar1 > BUCKET
  elif test -f $tar1 ; then
    cp $tar1 BUCKET
  else
    echo 'input not found'
  fi
elif test -f $tar ; then
  cp $tar BUCKET
else
  echo 'input not found'
fi

time ruby bufr2synop -o'FMT=IA2,HIN=HIST.txt,HOUT=HNEW.txt,FILE=TAC.txt' \
  BUCKET:AHL='^IS.... BABJ'
test ! -f HNEW.txt || mv -f HNEW.txt HIST.txt
test ! -s TAC.txt || mv -f TAC.txt SYNOP-${dd}${hh}${nn}.txt

time ruby bufr2temp -o'FMT=IA2,HIN=HIST.txt,HOUT=HNEW.txt,FILE=TAC.txt' \
  BUCKET:AHL='^IUS... BABJ'
test ! -f HNEW.txt || mv -f HNEW.txt HIST.txt
test ! -s TAC.txt || mv -f TAC.txt TEMP-${dd}${hh}${nn}.txt

time ruby bufr2pilot -o'FMT=IA2,HIN=HIST.txt,HOUT=HNEW.txt,FILE=TAC.txt' \
  BUCKET:AHL='^IU.... BABJ'
test ! -f HNEW.txt || mv -f HNEW.txt HIST.txt
test ! -s TAC.txt || mv -f TAC.txt PILOT-${dd}${hh}${nn}.txt

rm -f BUCKET

find . -ctime +5 -name '*-*.txt' | xargs rm -f
set +x
exec 2>&3
grep ': ' ${LOGFILE} || true
test -s ${LOGFILE} || rm -f ${LOGFILE}
