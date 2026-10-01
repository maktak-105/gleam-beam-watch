import beam_watch
import filepath
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/http
import gleam/http/request
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import mist
import simplifile
import wisp.{type Request, type Response}
import wisp/wisp_mist

const port = 3000

const check_interval_ms = 5000

const check_attempts = 3

const check_wait_ms = 60_000

const result_history_limit = 100

pub type Target {
  Target(id: Int, url: String)
}

pub type ResultRow {
  ResultRow(
    url: String,
    status: String,
    http_status: Option(Int),
    timestamp: String,
  )
}

type State {
  State(
    next_id: Int,
    targets: List(Target),
    results: List(ResultRow),
    checking: Bool,
    queued: Option(Subject(Result(Nil, String))),
  )
}

type CheckReply {
  NoReply
  ReplyTo(Subject(Result(Nil, String)))
}

type Msg {
  Add(url: String, reply: Subject(Result(Target, String)))
  Delete(id: Int, reply: Subject(Bool))
  Snapshot(reply: Subject(#(List(Target), List(ResultRow))))
  StartCheck(reply: CheckReply)
  CheckDone(rows: List(ResultRow), reply: CheckReply)
  Tick
}

type Context {
  Context(store: Subject(Msg), gui_dir: String)
}

pub fn main() {
  case start() {
    Ok(_) -> process.sleep_forever()
    Error(reason) -> io.println("GUIサーバーを起動できませんでした: " <> reason)
  }
}

pub fn start() -> Result(Nil, String) {
  wisp.configure_logger()
  let gui_dir = gui_directory()
  let index = filepath.join(gui_dir, "index.html")
  use _ <- result.try(case simplifile.is_file(index) {
    Ok(True) -> Ok(Nil)
    _ -> Error("画面ファイルが見つかりません: " <> index)
  })

  let store = start_store()
  let context = Context(store:, gui_dir:)
  let secret = wisp.random_string(64)
  let handler = fn(request) { handle_request(request, context) }

  handler
  |> wisp_mist.handler(secret)
  |> mist.new
  |> mist.bind("127.0.0.1")
  |> mist.port(port)
  |> mist.start
  |> result.map(fn(_) {
    io.println("BEAM Watch GUI: http://127.0.0.1:" <> int.to_string(port))
    Nil
  })
  |> result.map_error(fn(err) {
    "ポート " <> int.to_string(port) <> " の待受に失敗しました: " <> string.inspect(err)
  })
}

fn gui_directory() -> String {
  case simplifile.current_directory() {
    Ok(dir) -> filepath.join(dir, "gui")
    Error(_) -> "gui"
  }
}

fn start_store() -> Subject(Msg) {
  let ready = process.new_subject()
  process.spawn(fn() {
    let self = process.new_subject()
    process.send(ready, self)
    process.send_after(self, check_interval_ms, Tick)
    loop(
      self,
      State(next_id: 1, targets: [], results: [], checking: False, queued: None),
    )
  })
  process.receive_forever(ready)
}

fn loop(self: Subject(Msg), state: State) -> Nil {
  case process.receive_forever(self) {
    Add(url, reply) -> {
      let #(state, added) = add_target(state, url)
      process.send(reply, added)
      let state = case added {
        Ok(_) -> begin_check(self, state, NoReply)
        Error(_) -> state
      }
      loop(self, state)
    }
    Delete(id, reply) -> {
      let #(state, removed) = delete_target(state, id)
      process.send(reply, removed)
      loop(self, state)
    }
    Snapshot(reply) -> {
      process.send(reply, #(state.targets, state.results))
      loop(self, state)
    }
    StartCheck(reply) -> loop(self, begin_check(self, state, reply))
    CheckDone(rows, reply) -> {
      let queued = state.queued
      let rows =
        list.filter(rows, fn(row) {
          list.any(state.targets, fn(target) { target.url == row.url })
        })
      let state =
        State(
          ..state,
          checking: False,
          queued: None,
          results: remember(state.results, rows),
        )
      case reply {
        ReplyTo(subject) -> process.send(subject, Ok(Nil))
        NoReply -> Nil
      }
      let state = case queued {
        Some(subject) -> begin_check(self, state, ReplyTo(subject))
        None -> state
      }
      loop(self, state)
    }
    Tick -> {
      process.send_after(self, check_interval_ms, Tick)
      loop(self, begin_check(self, state, NoReply))
    }
  }
}

fn add_target(state: State, url: String) -> #(State, Result(Target, String)) {
  let url = string.trim(url)
  case url {
    "" -> #(state, Error("URLを入力してください"))
    _ -> {
      case request.to(url) {
        Error(_) -> #(state, Error("URLが不正です"))
        Ok(_) -> {
          case list.find(state.targets, fn(target) { target.url == url }) {
            Ok(_) -> #(state, Error("すでに登録されています"))
            Error(_) -> {
              let target = Target(id: state.next_id, url:)
              let state =
                State(
                  ..state,
                  next_id: state.next_id + 1,
                  targets: list.append(state.targets, [target]),
                )
              #(state, Ok(target))
            }
          }
        }
      }
    }
  }
}

fn delete_target(state: State, id: Int) -> #(State, Bool) {
  case list.find(state.targets, fn(target) { target.id == id }) {
    Error(_) -> #(state, False)
    Ok(target) -> {
      let state =
        State(
          ..state,
          targets: list.filter(state.targets, fn(item) { item.id != id }),
          results: list.filter(state.results, fn(row) { row.url != target.url }),
        )
      #(state, True)
    }
  }
}

fn begin_check(self: Subject(Msg), state: State, reply: CheckReply) -> State {
  case state.checking {
    True -> queue_check(state, reply)
    False -> {
      case state.targets {
        [] -> {
          reply_ok(reply)
          state
        }
        targets -> {
          process.spawn_unlinked(fn() {
            process.send(self, CheckDone(check_all(targets), reply))
          })
          State(..state, checking: True)
        }
      }
    }
  }
}

fn queue_check(state: State, reply: CheckReply) -> State {
  case reply {
    NoReply -> state
    ReplyTo(subject) -> {
      case state.queued {
        Some(_) -> {
          process.send(subject, Error("チェック実行中です"))
          state
        }
        None -> State(..state, queued: Some(subject))
      }
    }
  }
}

fn reply_ok(reply: CheckReply) -> Nil {
  case reply {
    ReplyTo(subject) -> process.send(subject, Ok(Nil))
    NoReply -> Nil
  }
}

fn check_all(targets: List(Target)) -> List(ResultRow) {
  let incoming = process.new_subject()
  list.each(targets, fn(target) {
    process.spawn_unlinked(fn() {
      let outcome = beam_watch.check(target.url, check_attempts)
      process.send(incoming, row_for(target.url, outcome))
    })
  })
  collect(incoming, list.length(targets), [])
}

fn collect(
  incoming: Subject(ResultRow),
  remaining: Int,
  rows: List(ResultRow),
) -> List(ResultRow) {
  case remaining {
    0 -> rows
    _ -> {
      case process.receive(incoming, within: check_wait_ms) {
        Ok(row) -> collect(incoming, remaining - 1, [row, ..rows])
        Error(_) -> rows
      }
    }
  }
}

fn row_for(url: String, outcome: beam_watch.Outcome) -> ResultRow {
  let timestamp = now_iso8601()
  case outcome {
    beam_watch.Healthy(status) ->
      ResultRow(url:, status: "OK", http_status: Some(status), timestamp:)
    beam_watch.HttpFailure(status) ->
      ResultRow(url:, status: "NG", http_status: Some(status), timestamp:)
    beam_watch.Unreachable ->
      ResultRow(url:, status: "NG", http_status: None, timestamp:)
  }
}

fn remember(
  previous: List(ResultRow),
  rows: List(ResultRow),
) -> List(ResultRow) {
  list.append(rows, previous)
  |> list.take(result_history_limit)
}

@external(erlang, "gui_server_ffi", "now_iso8601")
fn now_iso8601() -> String

fn handle_request(request: Request, context: Context) -> Response {
  use <- wisp.log_request(request)
  case request.method, request.path_segments(request) {
    http.Options, _ -> with_cors(wisp.no_content())
    _, ["api", ..rest] -> with_cors(handle_api(request, rest, context))
    http.Get, [] -> index_html(context.gui_dir)
    _, _ -> {
      use <- wisp.serve_static(request, under: "/", from: context.gui_dir)
      wisp.not_found()
    }
  }
}

fn handle_api(
  request: Request,
  path: List(String),
  context: Context,
) -> Response {
  case request.method, path {
    http.Get, ["targets"] -> json_ok(encode_targets(snapshot(context).0), 200)
    http.Get, ["results"] -> json_ok(encode_results(snapshot(context).1), 200)
    http.Post, ["targets"] -> add_from_request(request, context)
    http.Delete, ["targets", id] -> delete_from_request(context, id)
    http.Post, ["check"] -> check_now(context)
    _, _ -> json_error("見つかりません", 404)
  }
}

fn snapshot(context: Context) -> #(List(Target), List(ResultRow)) {
  process.call(context.store, waiting: check_wait_ms, sending: Snapshot)
}

fn add_from_request(request: Request, context: Context) -> Response {
  use body <- wisp.require_json(request)
  case decode.run(body, url_decoder()) {
    Error(_) -> json_error("URLを入力してください", 400)
    Ok(url) -> {
      let added =
        process.call(context.store, waiting: check_wait_ms, sending: fn(reply) {
          Add(url, reply)
        })
      case added {
        Ok(target) -> json_ok(encode_target(target), 201)
        Error(message) -> json_error(message, 400)
      }
    }
  }
}

fn delete_from_request(context: Context, id: String) -> Response {
  case int.parse(id) {
    Error(_) -> json_error("IDが不正です", 400)
    Ok(id) -> {
      let removed =
        process.call(context.store, waiting: check_wait_ms, sending: fn(reply) {
          Delete(id, reply)
        })
      case removed {
        True -> json_ok(json.object([#("ok", json.bool(True))]), 200)
        False -> json_error("対象が見つかりません", 404)
      }
    }
  }
}

fn check_now(context: Context) -> Response {
  let checked =
    process.call(context.store, waiting: check_wait_ms, sending: fn(reply) {
      StartCheck(ReplyTo(reply))
    })
  case checked {
    Ok(_) -> json_ok(json.object([#("ok", json.bool(True))]), 200)
    Error(message) -> json_error(message, 409)
  }
}

fn url_decoder() -> decode.Decoder(String) {
  use url <- decode.field("url", decode.string)
  decode.success(url)
}

fn encode_targets(targets: List(Target)) -> json.Json {
  json.object([#("targets", json.array(targets, encode_target))])
}

fn encode_target(target: Target) -> json.Json {
  json.object([
    #("id", json.int(target.id)),
    #("url", json.string(target.url)),
  ])
}

fn encode_results(rows: List(ResultRow)) -> json.Json {
  json.object([#("results", json.array(rows, encode_result))])
}

fn encode_result(row: ResultRow) -> json.Json {
  json.object([
    #("url", json.string(row.url)),
    #("status", json.string(row.status)),
    #("http_status", json.nullable(row.http_status, json.int)),
    #("timestamp", json.string(row.timestamp)),
  ])
}

fn json_ok(body: json.Json, status: Int) -> Response {
  wisp.json_response(json.to_string(body), status)
}

fn json_error(message: String, status: Int) -> Response {
  json_ok(json.object([#("error", json.string(message))]), status)
}

fn with_cors(response: Response) -> Response {
  response
  |> wisp.set_header("access-control-allow-origin", "*")
  |> wisp.set_header(
    "access-control-allow-methods",
    "GET, POST, DELETE, OPTIONS",
  )
  |> wisp.set_header("access-control-allow-headers", "content-type")
}

fn index_html(gui_dir: String) -> Response {
  let path = filepath.join(gui_dir, "index.html")
  wisp.response(200)
  |> wisp.set_header("content-type", "text/html; charset=utf-8")
  |> wisp.set_body(wisp.File(path:, offset: 0, limit: None))
}
