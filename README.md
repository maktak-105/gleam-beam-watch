# BEAM Watch

Gleam と BEAM の並行処理を試すための、複数 URL の死活監視 CLI です。

## 動作

URL ごとに軽量な BEAM プロセスを起動します。各ワーカーは HTTP リクエストを行い、結果をメインプロセスへ型付きメッセージで返します。そのため、遅い URL がほかの URL の結果表示を止めません。

```text
URL 1 ──> BEAM ワーカー ──┐
URL 2 ──> BEAM ワーカー ──┼──> メインプロセス ──> 結果を到着順に表示
URL 3 ──> BEAM ワーカー ──┘
```

- HTTP 2xx / 3xx: `OK`
- HTTP 4xx / 5xx: `NG`
- 接続失敗・不正 URL: `NG`
- HTTPタイムアウト: 5秒
- 再試行: 最大3回（正常応答は再試行しない）
- HTTPS: TLS証明書を検証する。検証を無効化しない。

## 必要なもの

- [Gleam](https://gleam.run/install/)
- Erlang/OTP 27以降（OTP 29を推奨）

## 実行

```powershell
gleam run -- https://gleam.run https://example.com https://example.invalid
```

出力は入力順ではなく、各チェックが完了した順番です。

```text
OK  https://gleam.run (HTTP 200)
NG  https://example.invalid (接続失敗または不正な URL)
```

引数なしで実行すると、使い方を表示します。

## テスト

```powershell
gleam format --check
gleam test
```

## 実装メモ

`src/beam_watch.gleam` にGleamの監視ロジックがあります。`src/beam_watch_ffi.erl` は、OTPのHTTPクライアント内部で例外が起きた場合にもワーカーが必ず失敗結果を返せるようにする、最小限のErlangラッパーです。
