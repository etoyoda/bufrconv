#!/bin/bash
set -xEeuo pipefail

if getent passwd nwp >/dev/null; then
  INSTALL_USER=nwp
  CRON=true
else
  INSTALL_USER=$(id -un)
  CRON=false
fi

test -d /nwp/bin
for prog in \
	run-plot.sh bufrsort distillobs.rb sort2sfcmap.rb sort2uprmap.rb bufr2pick \
	bufrscan.rb bufrdump.rb
do
	sudo -u $INSTALL_USER install -C -m 0755 $prog /nwp/bin
done
test -d /nwp/share/bufrconv || sudo -u $INSTALL_USER mkdir -p /nwp/share/bufrconv
for table in \
	table_b_bufr table_b_bufr.v13 table_c11 table_d_bufr table_station
do
	sudo -u $INSTALL_USER install -C -m 0644 share/$table /nwp/share/bufrconv/$table
	# purge older installation
	test ! -f /nwp/bin/$table || sudo -u $INSTALL_USER rm -f /nwp/bin/$table
done
if $CRON
then
	sudo install -m 0644 crontab.txt /etc/cron.d/bufrconv
fi
