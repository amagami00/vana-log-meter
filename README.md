# vana-log-meter

FFXI クライアントのチャットログ（`FINAL FANTASY XI/TEMP/{1,2}_{0..19}.log`）を読み、戦闘を集計するツール。
Windows と Mac を対象にする。

## 読み取る範囲

- **ログファイルを読むだけ**。ゲームのメモリやパケットには触れない。ゲームへの書き込みもしない。
- ログに出ない値（時刻・命中判定の内訳など）は取得できない。

## 構成

| ディレクトリ | 内容 |
|---|---|
| `packages/vana_log_core` | ログの解析・集計・CSV/JSON 出力（Dart。UI を持たない） |
| `app` | 監視・集計・書き出しの画面（Flutter。Windows / macOS） |
