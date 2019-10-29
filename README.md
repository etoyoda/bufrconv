# burconv
a quick-hack pure-ruby program to convert BUFR into usable formats (TAC or JSON planned).
supported templates: SYNOP and TEMP (so far planned).

# ツール利用法

**出来上がったら書きます。まだ変える**

# 設計メモ

bufr は grib に似た節構造。第３節にデータ記述があって、第４節にデータ本体がある。
やりにくいのは、繰り返し数がデータ本体に埋め込まれる場合があることで、第４節のビット位置の意味付けや結果のインフォセット形状は第４節を読みながらでしか決定しない。
圧縮には対応しない。事実上使われないものと思われる。

# acknowledgement
BUFR tables (files table_b_bufr and table_d_bufr) are taken from libECBUFR https://launchpad.net/libecbufr

