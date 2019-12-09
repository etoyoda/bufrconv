# bufrconv
A quick-hack pure-ruby program to convert BUFR into usable formats (TAC or JSON).

WMO 通報式 [BUFR](BUFR.md) を解読し TAC や JSON などのより利用しやすい形式に
変換する pure ruby プログラム。

# ツール利用法

## BUFR表なしでできる処理

ファイルは必ずしも "BUFR" から始まらなくてもよい。BUFR を含むバッチFTPファイル、tar ファイルなどでもかまわない。
詳細は [bufrscan.md](bufrscan.md) 参照。

> **ruby bufrscan.rb** _files ..._

files から BUFR 報を見出し、概要（第１節など固定位置に書かれた情報）を印字する。

> **ruby bufrscan.rb -d** _files ..._

files から BUFR 報を見出し、記述子列を印字する。


## BUFR表を参照するがすべてのBUFRに通用する処理

詳細は [bufrdump.md](bufrdump.md) 参照。
BUFR表については後述。

> **ruby bufrdump.rb -x** _files ..._

記述子列の反復の範囲を判定し、集約を展開 (eXpand) した結果を
JSON 形式で印字する。

> **ruby bufrdump.rb -c** _files ..._

記述子列の反復の範囲を判定し、集約を展開し、
要素記述子の幅・単位・尺度・名称を調べ、操作記述子を適用して解読計画を
構成 (compile) した結果を
JSON 形式で印字する。

> **ruby bufrdump.rb -d** _files ..._

電文中の実データを毎行1要素の形式で印字 (dump) する。

> **ruby bufrdump.rb -j** _files ..._

電文中の実データをサブセット毎に JSON 形式で印字する。

## 特定のテンプレートを持つBUFR報に適用できる処理

> **ruby bufr2synop.rb** _files ..._

FM12 SYNOP 通報式を生成する。

> **ruby bufr2temp.rb** _files ..._

FM35 TEMP 通報式を生成する。現在のところ Part A だけが生成される。

# BUFR表について

BUFR表はファイル `table_b_bufr`, `table_b_bufr.v13`, `table_d_bufr`
に格納される。
これらはデフォルトでは ruby スクリプト `$0` が置かれたディレクトリから
探されるが、環境変数 `BUFRDUMPDIR` を定義することにより変更できる。

# 制約

* operator descriptors はほとんど実装されていない。

# Acknowledgement

BUFR tables (files `table_b_bufr` and `table_d_bufr`) are taken from libECBUFR https://launchpad.net/libecbufr which is also distributed under LGPL.
