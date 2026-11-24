# vana_log_core

FFXI のチャットログを解析し、戦闘の事実を CSV に書き出す Dart パッケージ。

## 使い方

```sh
dart run bin/vana_log.dart -i <TEMP のディレクトリ> -o <出力先> [-w 1|2]
```

- 読解率（戦闘の行のうち読めた割合）を表示する。`--show-unparsed` で読めなかった行も出す。
- 出力は `vanalog-YYYYMMDD-HHMMSS-events.csv`（`CsvRecorder` も同じ名前）。CSV は UTF-8（BOM 付き）・CRLF。`CsvRecorder` は戦闘の行そのものも `vanalog-YYYYMMDD-HHMMSS-raw.tsv`（タブ区切り、名前は置き換えない）に書く。
- 列名は battlelog の CSV に合わせ、ネイティブログから取れる列だけを出す。
- `RecordedLog.addCsv` で記録した CSV を読み戻し、監視中と同じ形で集計する（CSV の読み取りは `package:csv`）。

## ログの形式

- 先頭 100 バイトは行オフセット表（uint16 LE × 50。`0xFFFF` は未使用）。
- 各行は 16 進のフィールド 21 個、CP932 の本文、終端 `\x00`。
- 本文の制御コード（`\x1e?` `\x1f?` `\x7f?` `\xef\x27` `\xef\x28`）はバイト列のまま処理してから変換する。

## 既知の制限

- 追加ダメージと技連携の行為者は、直前の攻撃から推定する（`actor_inferred` = 1）。
- 遠隔攻撃のサンプルがなく、未対応。
- ウィンドウ 1 と 2 は、出す種類の設定しだいで同じ内容にも別の内容にもなる。
  メッセージの番号（4 番目のフィールド）は両ウィンドウで共通の通し番号で、同じメッセージは同じ番号・同じ本文になる。
  `LogSession(window: bothWindows)` はこれを使い、両方を重複なく番号順にまとめて集計する（`WindowMerger`）。
- 一括読み込みでは `time` / `elapsed` が空になる（監視中に観測した時刻だけを入れる）。
- 同名の敵を区別できない。

## CP932 の変換表

`lib/src/cp932_table.dart` は Python の `cp932` から生成する。

```sh
python3 -I tool/gen_cp932_table.py > lib/src/cp932_table.dart
```

pub の `charset` パッケージは、途切れた 2 バイト文字で例外を投げ、IBM 拡張（ED/EE・FA〜FC）を
持たないため使わない。
