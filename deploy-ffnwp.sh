#!/bin/bash
set -Ceuxo pipefail
test -d /nwp/bin
sudo -u nwp cp run-plot.sh bufrsort sort2sfcmap.rb table_* /nwp/bin
