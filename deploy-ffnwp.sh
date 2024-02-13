#!/bin/bash
set -Ceuxo pipefail
test -d /nwp/bin
sudo -u nwp cp run-plot.sh bufrsort distillobs.rb sort2sfcmap.rb sort2uprmap.rb table_* bufr2pick /nwp/bin
