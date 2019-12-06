# bufrscan.rb - 低レベルBUFRデコーダ

BUFR 表を必要としない固定位置情報（第１節など）の解読と、
ビット列の解読を行います。
BUFR の構造については [BUFR.md](BUFR.md) を参照してください。

# 単独での使用

> ruby **bufrscan.rb** _files ..._

任意の形式のファイル _files_ を開いて BUFR 報をすべて抽出し、
各 BUFR 報について第1節などの主要部情報 (TBD) を JSON 形式で印字します。

## ヘッダ選択オプション

> ruby **bufrscan.rb** _file_**:AHL=**_regexp_ ...

ファイル名に **:AHL=**_regexp_ を後置すると、
BUFR 報の直前に GTS 電文ヘッダ行が認識できる場合、
正規表現 _regexp_ にマッチしないヘッダ行がある BUFR 報を処理対象から除外します。

たとえば `obsbf-2019-11-06.tar:AHL=^IS` であれば
ヘッダ行が `IS` で始まる BUFR 報が選ばれます。
キャレット `^` をつけないと、ヘッダ行の途中に `IS` がある場合も対象となります。
字数が多ければ、
たとえば `:AHL=RJTD` であればおそらくヘッダ先頭ではなく発信中枢略号が
RJTD （日本東京気象庁）が選ばれるものと思われます。保証はないけど手早いです。

**警告**: 正規表現は Ruby の正規表現です。
任意コード実行ができる Perl の正規表現ほど危険ではありませんが、
工夫すれば無限ループによる DOS 攻撃くらいはできるので、
信用できない他人がもたらした入力を正規表現にするのはやめましょう。

## 出力内容変更オプション

> ruby **bufrscan.rb** -d _files ..._

各 BUFR 報について記述子列をコンマ区切りで印字します。
集約を展開しないので、第3節に書かれている記述子列がそのまま得られます。

> ruby **bufrscan.rb** -fctr _files ..._

各 BUFR 報について発信中枢番号をコンマ区切りで印字します。


# ライブラリ

## class BUFRScan 

任意の形式のファイルについて BUFR 報を抽出し BUFRMsg クラス値を構築します。

### BUFRScan.filescan(_fnam_) {|msg| ... }

基本的にこれを使ってください。

ファイル _fnam_ をバイナリモードで開き、BUFR 報が見つかるたびに
yield で BUFRMsg クラスの値を投げ返します。

### BUFRScan.new(_io_, _fnam_ = '-')

既に開かれている _io_ （必ずしもディスクファイルである必要はなく、
read(_n_) が文字列を返す何か）について BUFRScan を構築して返します。

### BUFRScan#scan {|bufrmsg| ... }

構築時に与えた _io_ を読みだして BUFR 報が見つかるたびに
BUFRMsg を構築して yield で投げ返します。


## class BUFRMsg

### BUFRMsg.new _buf_, _ofs_, _msglen_, _fnam_ = '-', _ahl_ = nil

文字列 _buf_ の _ofs_ オクテット目（先頭がゼロ）から
_msglen_ 個オクテットを BUFR 報として解読する準備を始めます。

必須ではありませんがファイル名 _fnam_ や GTS ヘッダ _ahl_ を与えると
エラーメッセージがわかりやすくなります。

このクラス内部には、readnum または readstr でビット単位の読み出しを行う
現在位置ポインタが保持され、その初期値は第４節のビット列の先頭にセットされます
(後述 ptrcheck 参照)。

### BUFRMsg#to_h

固定位置に書かれた情報、つまり第１節各欄および
第３節（サブセット数、フラグ、記述子列）を解読し、
ハッシュで返します。

### BUFRMsg#[_key_]

to_h[_key_] を返します（なければ nil）。

### BUFRMsg#ahl

構築時に与えられたヘッダ行（デフォルト nil）を返します。

### BUFRMsg#compressed?

BUFR 第1節のフラグにより圧縮形式とされる場合に真を返します。

### BUFRMsg#readnum _desc_



### BUFRMsg#readstr _desc_

TBD

### BUFRMsg#ymdhack _opts_

TBD
