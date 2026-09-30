// GUIサーバーのメインモジュール
import gleam/http
import gleam/httpd
import gleam/http/request
import gleam/http/response
import gleam/json
import gleam/list
import gleam/string
import gleam/option
import gleam/map
import gleam/result
import gleam/int
import gleam/queue
import beam_watch

// 監視対象URLの型定義
pub type WatchTarget {
  WatchTarget(url: String, id: Int)
}

// 監視結果の型定義
pub type WatchResult {
  WatchResult(
    id: Int,
    url: String,
    status: String,
    http_status: Option(Int),
    timestamp: String
  )
}

// サーバー状態
pub type ServerState {
  ServerState(
    targets: List(WatchTarget),
    results: Map(Int, WatchResult)
  )
}

// 初期状態の作成
pub fn initial_state() -> ServerState {
  ServerState(targets: [], results: map.new())
}

// 新しい監視対象を追加
pub fn add_target(state: ServerState, url: String) -> ServerState {
  let id = case list.length(state.targets) {
    0 -> 1
    n -> n + 1
  }
  let new_target = WatchTarget(url: url, id: id)
  let new_targets = list.append(state.targets, new_target)
  ServerState(targets: new_targets, results: state.results)
}

// 監視対象を削除
pub fn remove_target(state: ServerState, id: Int) -> ServerState {
  let new_targets = list.filter(state.targets, fn(target) { target.id != id })
  let new_results = map.remove(state.results, id)
  ServerState(targets: new_targets, results: new_results)
}

// 監視結果を更新
pub fn update_result(state: ServerState, result: WatchResult) -> ServerState {
  let new_results = map.set(state.results, result.id, result)
  ServerState(targets: state.targets, results: new_results)
}

// JSON変換関数
pub fn target_to_json(target: WatchTarget) -> String {
  json.encode(
    json.object([
      ("id", json.int(target.id)),
      ("url", json.string(target.url))
    ])
  )
}

pub fn result_to_json(result: WatchResult) -> String {
  json.encode(
    json.object([
      ("id", json.int(result.id)),
      ("url", json.string(result.url)),
      ("status", json.string(result.status)),
      ("http_status", json.maybe(result.http_status, json.int)),
      ("timestamp", json.string(result.timestamp))
    ])
  )
}

// 監視結果のJSON変換
pub fn results_to_json(results: Map(Int, WatchResult)) -> String {
  let result_list = map.values(results)
  let json_array = 
    result_list
    |> list.map(result_to_json)
    |> string.join_with(", ")
  "[ " <> json_array <> " ]"
}

// 監視対象のJSON変換
pub fn targets_to_json(targets: List(WatchTarget)) -> String {
  let json_array = 
    targets
    |> list.map(target_to_json)
    |> string.join_with(", ")
  "[ " <> json_array <> " ]"
}

// HTTPハンドラー
pub fn handle_get_targets(request: http.Request, state: ServerState) -> http.Response {
  let targets_json = targets_to_json(state.targets)
  response.ok(
    json.object([
      ("targets", json.string(targets_json))
    ])
  )
}

pub fn handle_post_target(request: http.Request, state: ServerState) -> http.Response {
  // TODO: URLの取得と追加処理
  // 現在はダミーのレスポンス
  response.ok(json.object([("status", json.string("success"))]))
}

pub fn handle_delete_target(request: http.Request, state: ServerState) -> http.Response {
  // TODO: 削除処理
  // 現在はダミーのレスポンス
  response.ok(json.object([("status", json.string("success"))]))
}

// サーバーの起動
pub fn start_server() {
  let state = initial_state()
  
  let handler = fn(request, _state) {
    case request.method {
      "GET" -> 
        if string.is_prefix("/api/targets", request.path) {
          handle_get_targets(request, state)
        } else if string.is_prefix("/api/results", request.path) {
          // TODO: 結果取得処理
          response.ok(json.object([("results", json.string("[]"))]))
        } else {
          response.not_found()
        }
      "POST" -> 
        if string.is_prefix("/api/targets", request.path) {
          handle_post_target(request, state)
        } else if string.is_prefix("/api/check", request.path) {
          // TODO: チェック処理
          response.ok(json.object([("status", json.string("success"))]))
        } else {
          response.not_found()
        }
      "DELETE" -> 
        if string.is_prefix("/api/targets/", request.path) {
          handle_delete_target(request, state)
        } else {
          response.not_found()
        }
      _ -> response.method_not_allowed()
    }
  }
  
  httpd.start(handler, port: 3000)
}