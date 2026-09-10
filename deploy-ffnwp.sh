#!/bin/bash
set -xEeuo pipefail
test -d /nwp/bin
for prog in
	run-plot.sh bufrsort distillobs.rb sort2sfcmap.rb sort2uprmap.rb bufr2pick
	bufrscan.rb bufrdump.rb
do
	sudo -u nwp install -C -m 0755 $prog /nwp/bin
done
test -d /nwp/share/bufrconv || sudo -u nwp mkdir -p /nwp/share/bufrconv
for table in
	table_b_bufr table_b_bufr.v13 table_c11 table_d_bufr table_station
do
	sudo -u nwp install -C -m 0644 share/$table /nwp/share/bufrconv/$table
	# purge older installation
	test ! -f /nwp/bin/$table || sudo -u nwp rm -f /nwp/bin/$table
done
sudo install -m 0644 crontab.txt /etc/cron.d/bufrconv
