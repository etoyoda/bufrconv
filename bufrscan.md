# bufrscan.rb - 低レベルBUFRデコーダ
## 単独での使用

> ruby **bufrscan.rb** _files ..._

任意の形式のファイル _files_ を開いて BUFR 報をすべて抽出し、
第1節などの主要部情報を JSON 形式で印字する。

> ruby **bufrscan.rb** _file_**:AHL=**_regexp_ ...

BUFR 報の直前に GTS 電文ヘッダ行が認識できる場合は正規表現
_regexp_ にマッチするヘッダ行があるものだけを処理対象とする。




## ライブラリ
