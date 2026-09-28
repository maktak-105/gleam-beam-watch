# BEAM Watch 開発記録

## 企画

- 目的: Gleam と BEAM の並行処理を学ぶため、複数 URL を同時に確認する死活監視 CLI を作る。
- 実行基盤: Erlang/OTP 上の BEAM。
- 入力: コマンドライン引数として 1 個以上の URL を渡す。
- 判定: HTTP 2xx/3xx は `OK`、4xx/5xx・接続失敗・URL 不正は `NG`。
- 信頼性: 1 URL ごとに最大 3 回試行し、各試行の HTTP タイムアウトは 5 秒とする。

## 設計

- メインプロセスが結果受信用の `Subject` を作る。
- URL ごとに BEAM の軽量プロセスを起動する。
- 各ワーカーは HTTP を確認し、型付きの結果メッセージをメインプロセスへ送る。
- メインプロセスは到着順に結果を表示する。したがって遅い URL が他の URL の表示を妨げない。
- OTP の HTTP クライアント内部の例外は最小の Erlang FFI で `Error(Nil)` に変換し、ワーカーが結果を返さず終了しないようにする。

## 実装

- 状態: 完了
- 実装内容: Gleam の `process.spawn_unlinked` と `Subject` を使い、URLごとに並行ワーカーを起動するCLIを実装した。
- 依存関係: `argv`、`gleam_erlang`、`gleam_httpc`、`gleam_http`、`gleam_stdlib`、テスト用の `gleeunit` を追加した。

## 評価

- 状態: 合格
- `gleam format --check`: 合格
- `gleam test`: 3件合格
- 実通信: `http://httpbin.org/status/200` は `OK (HTTP 200)`、`http://httpbin.org/status/404` は `NG (HTTP 404)`、`http://example.invalid` は `NG` を返すことを確認した。結果は入力順ではなく到着順に表示された。
- 補足: このサンドボックスのポータブルOTPはWindows証明書ストアを読み込めず、HTTPS開始時にOTP内部例外が起きた。この例外は `NG` として処理され、TLS証明書検証を無効化していない。
