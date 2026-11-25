# BEAM Watch

Gleam と BEAM の並行処理を試すための、複数 URL の死活監視 CLI です。

## 状態

死活は「ブラウザ（Edge のヘッドレス）で開いてページが出たか」で決めます。AI195417 では、タスク `Beam-watch` をサーバーのアカウント `GLOBAL\AAdmZ100DB110`（パスワード保存）で動かします。SYSTEM では Edge がページを出せない（終了コード 1002、取得 0 バイト）ためです。経緯と検証結果は `plans/2026-11-25_ブラウザ死活判定_v1.4.md` と同じ日付の結果ファイルにあります。

## 動作

URL ごとにブラウザでページを開きます。各ワーカーは結果をメインプロセスへ型付きメッセージで返します。そのため、遅い URL がほかの URL の結果表示を止めません。

```text
URL 1 ──> BEAM ワーカー ──┐
URL 2 ──> BEAM ワーカー ──┼──> メインプロセス ──> 結果を到着順に表示
URL 3 ──> BEAM ワーカー ──┘
```

- ブラウザで開いてページが出た: `OK`
- ページが出ない、時間切れ、接続できない: `NG`。理由には Edge のエラーコードを付けます（例: `接続を拒否された (ERR_CONNECTION_REFUSED)`）。
- 1件につきブラウザで1回開く。状態コードでは決めない。
- 人事DB（`https://ai195417:8766/`）の自己署名証明書は、`deploy/server/BrowserCheck.ps1` が起動する Edge にだけ、公開鍵のハッシュで信頼させます（`--ignore-certificate-errors-spki-list`）。証明書ストアは変えません。

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

`AI195417` ではタスク `Beam-watch` が起動時から常駐し、http://AI195417:8010/ で画面を出します。実行アカウントは `GLOBAL\AAdmZ100DB110`（ログオン種別 Password）です。このアカウントには「バッチジョブとしてログオン」の権利が要り、`deploy/server/Grant-BatchLogonRight.ps1` で足します（変更前のユーザー権利は `C:\server\Apps\beam-watch\deploy\user-rights-backup-*.inf` に残ります）。配備手順は `deploy/Publish-ToServer.ps1` です。ID とパスワードは実行時に `bunai-server\サーバー.md` から読み、リポジトリやログには書きません。ファイアウォールは `bunai-server` の PostgreSQL 規則と同じ3範囲（`172.26.208.0/20`、`10.178.32.0/20`、`160.203.88.0/24`）の Domain プロファイルだけを許可します。

監視するのは社内アドレスだけです。対象は、ポータル（`C:\server\Apps\portal`、80番の nginx）にエイリアスがあるアプリで、エイリアスの URL（例 `http://ai195417/myerp`）をブラウザで開きます。エイリアスのないポートと外部サイトは監視しません。BEAM Watch 自身（`/beam`）も対象外です。初期値は `deploy/ai195417-settings.json` の 9 件です。画面には、各対象のアプリ名・エイリアス・転送先を出します。これらは表示のたびにポータルの `nginx.conf` と `html/index.html` から読みます（場所は環境変数 `BEAM_WATCH_PORTAL_DIR` で変えられます）。

外部サイトを監視しない理由: AI195417 から `*.vercel.app` などへ出ると、社内の Web フィルター「TS セキュリティ共通基盤サービス」が、ログオン中のアカウント（AAdmZ100DB110）の規則で `web-hosting` 分類として止めます（2026-11-25 確認）。

確認結果は `data/history.sqlite3` に残します。列は URL、確認日時、死活結果（OK または NG）です。最大 10,000 件で、それより古い行は捨てます。画面には、登録した対象ごとの最新の OK / NG を全部出します。監視対象を削除すると、その URL の履歴も削除します。

Mist が Erlang パッケージ `hpack_erl` を使うため、ビルドには [rebar3](https://rebar3.org) が PATH 上に必要です。SQLite 連携の初回ビルドには C コンパイラも必要で、コマンド名は `cc` です。

## テスト

```powershell
gleam format --check
gleam test
```

## 実装メモ

`src/beam_watch.gleam` にGleamの監視ロジックがあります。`src/beam_watch_ffi.erl` は、OTPのHTTPクライアント内部で例外が起きた場合にもワーカーが必ず失敗結果を返せるようにする、最小限のErlangラッパーです。
