#!/bin/bash
set -Ceuo pipefail
PATH=/usr/local/bin:/usr/bin:/bin
LANG=C
TZ=UTC

set -x

: ${day:=today}

case $day in
today)
  day=incomplete
  ;;
yesterday)
  day=latest
  ;;
esac

test -d /nwp/p0/${day}

tar --wildcards -xvf /nwp/p0/${day}/obsbf-2*.tar* 'A_IS????BABJ*.bufr'
