# BEAM Watch

Gleam と BEAM の並行処理を試すための、複数 URL の死活監視 CLI です。

## 状態

未完成。死活を「ブラウザで開いてページが出たか」にする変更は、ローカルのコードまでです。AI195417 で動いている監視には載せていません。タスク `Beam-watch` は SYSTEM で動き、SYSTEM では Edge がページを出せません（終了コード 1002、取得 0 バイト）。このまま配備すると、登録した全件が NG になります。稼働中のサーバーは、従来の HTTP 状態コードによる判定のままです。

## 動作

URL ごとにブラウザでページを開きます。各ワーカーは結果をメインプロセスへ型付きメッセージで返します。そのため、遅い URL がほかの URL の結果表示を止めません。

```text
URL 1 ──> BEAM ワーカー ──┐
URL 2 ──> BEAM ワーカー ──┼──> メインプロセス ──> 結果を到着順に表示
URL 3 ──> BEAM ワーカー ──┘
```

- ブラウザで開いてページが出た: `OK`
- ページが出ない、時間切れ、接続できない: `NG`
- 1件につきブラウザで1回開く。状態コードでは決めない。

## 必要なもの

- [Gleam](https://gleam.run/install/)
- Erlang/OTP 27以降（OTP 29を推奨）

## 実行

```powershell
gleam run -- https://gleam.run https://example.com https://example.invalid
```

出力は入力順ではなく、各チェックが完了した順番です。

```text
OK  https://gleam.run (ページが出た)
NG  https://example.invalid (ページが出なかった)
```

引数なしで実行すると、使い方を表示します。

## GUI

ブラウザから URL を登録して、同じ判定を確認できます。CLI はそのまま `gleam run` です。

```powershell
gleam run -m gui_server
```

起動後に http://127.0.0.1:3000 を開きます。待受アドレスとポートは環境変数 `BEAM_WATCH_BIND` と `BEAM_WATCH_PORT` で変えられます。未設定のときは `127.0.0.1:3000` です。追加・削除・「今すぐチェック」と、設定した間隔の自動再チェックがあります。

## 部内サーバー

`AI195417` ではタスク `Beam-watch` が起動時から常駐し、http://AI195417:8010/ で画面を出します。配備手順は `deploy/Publish-ToServer.ps1` です。ファイアウォールは `bunai-server` の PostgreSQL 規則と同じ3範囲（`172.26.208.0/20`、`10.178.32.0/20`、`160.203.88.0/24`）の Domain プロファイルだけを許可します。

初期の監視対象は、2026-11-24 にこのサーバーで待受していた TCP ポート 45 件です。一覧は `deploy/ai195417-settings.json` にあります。確認はサーバー自身の `127.0.0.1` へ向けます。ポート 139 だけ待受が `172.26.213.150` だったため、そのアドレスを使います。8766 は HTTPS です。HTTP 以外のポートは、この監視の判定では NG になります。確認結果は `data/history.sqlite3` に残します。列は URL、確認日時、死活結果（OK または NG）です。最大 10,000 件で、それより古い行は捨てます。画面には、登録した対象ごとの最新の OK / NG を全部出します。監視対象を削除すると、その URL の履歴も削除します。

Mist が Erlang パッケージ `hpack_erl` を使うため、ビルドには [rebar3](https://rebar3.org) が PATH 上に必要です。SQLite 連携の初回ビルドには C コンパイラも必要で、コマンド名は `cc` です。

## テスト

```powershell
gleam format --check
gleam test
```

## 実装メモ

`src/beam_watch.gleam` にGleamの監視ロジックがあります。`src/beam_watch_ffi.erl` は、OTPのHTTPクライアント内部で例外が起きた場合にもワーカーが必ず失敗結果を返せるようにする、最小限のErlangラッパーです。
