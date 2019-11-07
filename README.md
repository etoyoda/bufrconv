# burconv
a quick-hack pure-ruby program to convert BUFR into usable formats (TAC or JSON planned).
supported templates: SYNOP and TEMP (so far planned).

# ツール利用法

> **ruby bufrscan.rb** _files ..._

files から BUFR 報を見出し、概要（第１節など固定位置に書かれた情報）を印字する。

> **ruby bufrscan.rb -d** _files ..._

files から BUFR 報を見出し、記述子列を印字する。

# 制約

* operator descriptors はほとんど実装されていない。
* 圧縮には対応しない。

# Acknowledgement

BUFR tables (files table_b_bufr and table_d_bufr) are taken from libECBUFR https://launchpad.net/libecbufr which is distributed under LGPL.

