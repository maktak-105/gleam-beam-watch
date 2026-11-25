import beam_watch
import check_history
import filepath
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/http
import gleam/http/request
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None}
import gleam/result
import gleam/string
import mist
import portal
import simplifile
import sqlight.{type Connection}
import wisp.{type Request, type Response}
import wisp/wisp_mist

const default_port = 3000

const default_interval_seconds = 300

const min_interval_seconds = 1

const max_interval_seconds = 86_400

const check_wait_ms = 120_000

const browser_slots = 4

const browser_result_wait_ms = 60_000

const default_portal_dir = "C:/server/Apps/portal"

pub type Target {
  Target(id: Int, url: String)
}

type Settings {
  Settings(check_interval_seconds: Int, check_interval_unit: String)
}

pub type ResultRow {
  ResultRow(
    url: String,
    status: String,
    http_status: Option(Int),
    detail: String,
    timestamp: String,
  )
}

type State {
  State(
    next_id: Int,
    targets: List(Target),
    db: Connection,
    check: CheckState,
    interval_seconds: Int,
    interval_unit: String,
    interval_generation: Int,
  )
}

/// チェックの進み具合。checking はチェック中、rerun は今の1周のあとにもう1周するか。
pub type CheckState {
  CheckState(checking: Bool, rerun: Bool)
}

/// チェックの依頼（今すぐチェック・URL の追加・自動チェック）への答え。
pub type CheckStart {
  Started
  Queued
  NoTargets
}

/// チェックを依頼されたときの次の状態。チェック中なら、今の1周のあとにもう1周する（何回来ても1周だけ）。
pub fn request_check(
  state: CheckState,
  target_count: Int,
) -> #(CheckState, CheckStart) {
  case state.checking, target_count {
    True, _ -> #(CheckState(checking: True, rerun: True), Queued)
    False, 0 -> #(state, NoTargets)
    False, _ -> #(CheckState(checking: True, rerun: False), Started)
  }
}

/// 1周が終わったときの次の状態と、もう1周するかどうか。
pub fn finish_check(state: CheckState) -> #(CheckState, Bool) {
  #(CheckState(checking: False, rerun: False), state.rerun)
}

type Msg {
  Add(url: String, reply: Subject(Result(Target, String)))
  Delete(id: Int, reply: Subject(Bool))
  Snapshot(reply: Subject(#(List(Target), List(ResultRow), Bool)))
  StartCheck(reply: Subject(CheckStart))
  CheckDone(rows: List(ResultRow))
  GetSettings(reply: Subject(Settings))
  SetSettings(
    seconds: Int,
    unit: String,
    reply: Subject(Result(Settings, String)),
  )
  Tick(generation: Int)
}

type Context {
  Context(
    store: Subject(Msg),
    gui_dir: String,
    settings_path: String,
    portal_dir: String,
    hosts: List(String),
  )
}

pub fn main() {
  case start() {
    Ok(_) -> process.sleep_forever()
    Error(reason) -> io.println("GUIサーバーを起動できませんでした: " <> reason)
  }
}

fn save_settings(
  path: String,
  settings: Settings,
  targets: List(Target),
) -> Result(Nil, String) {
  let json_content =
    json.object([
      #("checkIntervalSeconds", json.int(settings.check_interval_seconds)),
      #("checkIntervalUnit", json.string(settings.check_interval_unit)),
      #("targets", json.array(targets, encode_target)),
    ])
    |> json.to_string
  case simplifile.write(to: path, contents: json_content <> "\n") {
    Ok(_) -> Ok(Nil)
    Error(err) -> Error(string.inspect(err))
  }
}

fn load_settings(path: String) -> #(Settings, List(Target)) {
  let fallback = #(default_settings(), [])
  case simplifile.read(from: path) {
    Error(_) -> fallback
    Ok(content) -> {
      case json.parse(content, stored_decoder()) {
        Ok(stored) -> stored
        Error(_) -> fallback
      }
    }
  }
}

fn stored_decoder() -> decode.Decoder(#(Settings, List(Target))) {
  use seconds <- decode.optional_field(
    "checkIntervalSeconds",
    default_interval_seconds,
    decode.int,
  )
  use unit <- decode.optional_field(
    "checkIntervalUnit",
    "seconds",
    decode.string,
  )
  use targets <- decode.optional_field(
    "targets",
    [],
    decode.list(of: decode_target_decoder()),
  )
  decode.success(#(normalize_settings(seconds, unit), targets))
}

fn default_settings() -> Settings {
  Settings(
    check_interval_seconds: default_interval_seconds,
    check_interval_unit: "seconds",
  )
}

fn normalize_settings(seconds: Int, unit: String) -> Settings {
  let seconds = case seconds < min_interval_seconds {
    True -> min_interval_seconds
    False ->
      case seconds > max_interval_seconds {
        True -> max_interval_seconds
        False -> seconds
      }
  }
  let unit = case unit {
    "minutes" | "hours" -> unit
    _ -> "seconds"
  }
  Settings(check_interval_seconds: seconds, check_interval_unit: unit)
}

/// Target をデコードするデコーダー
fn decode_target_decoder() -> decode.Decoder(Target) {
  use id <- decode.field("id", decode.int)
  use url <- decode.field("url", decode.string)
  decode.success(Target(id:, url:))
}

pub fn start() -> Result(Nil, String) {
  wisp.configure_logger()
  let gui_dir = gui_directory()
  let index = filepath.join(gui_dir, "index.html")
  use _ <- result.try(case simplifile.is_file(index) {
    Ok(True) -> Ok(Nil)
    _ -> Error("画面ファイルが見つかりません: " <> index)
  })

  let settings_path = filepath.join(gui_dir, "settings.json")
  let #(settings, loaded_targets) = load_settings(settings_path)
  use store <- result.try(start_store(settings, loaded_targets, settings_path))
  let context =
    Context(
      store:,
      gui_dir:,
      settings_path:,
      portal_dir: configured_portal_dir(),
      hosts: this_server_hosts(),
    )
  let secret = wisp.random_string(64)
  let handler = fn(request) { handle_request(request, context) }

  let bind = configured_bind()
  let port = configured_port()

  handler
  |> wisp_mist.handler(secret)
  |> mist.new
  |> mist.bind(bind)
  |> mist.port(port)
  |> mist.start
  |> result.map(fn(_) {
    io.println("BEAM Watch GUI: http://" <> bind <> ":" <> int.to_string(port))
    Nil
  })
  |> result.map_error(fn(err) {
    "ポート " <> int.to_string(port) <> " の待受に失敗しました: " <> string.inspect(err)
  })
}

fn configured_bind() -> String {
  case getenv("BEAM_WATCH_BIND") {
    Ok(raw) ->
      case string.trim(raw) {
        "" -> "127.0.0.1"
        host -> host
      }
    Error(_) -> "127.0.0.1"
  }
}

fn configured_port() -> Int {
  case getenv("BEAM_WATCH_PORT") {
    Ok(raw) ->
      case int.parse(string.trim(raw)) {
        Ok(value) ->
          case value > 0 && value < 65_536 {
            True -> value
            False -> default_port
          }
        Error(_) -> default_port
      }
    Error(_) -> default_port
  }
}

// ポータル（nginx.conf と html/index.html）の場所。表示のたびに読むので、再起動なしで反映される。
fn configured_portal_dir() -> String {
  case getenv("BEAM_WATCH_PORTAL_DIR") {
    Ok(raw) ->
      case string.trim(raw) {
        "" -> default_portal_dir
        dir -> dir
      }
    Error(_) -> default_portal_dir
  }
}

// エイリアスの URL がこのサーバーのポータルを指しているかを決めるためのホスト名。
fn this_server_hosts() -> List(String) {
  case hostname() {
    "" -> ["localhost", "127.0.0.1"]
    name -> [name, "localhost", "127.0.0.1"]
  }
}

fn gui_directory() -> String {
  case simplifile.current_directory() {
    Ok(dir) -> filepath.join(dir, "gui")
    Error(_) -> "gui"
  }
}

fn start_store(
  settings: Settings,
  initial_targets: List(Target),
  settings_path: String,
) -> Result(Subject(Msg), String) {
  let ready = process.new_subject()
  process.spawn(fn() {
    case check_history.open(data_directory()) {
      Error(reason) -> process.send(ready, Error(reason))
      Ok(db) -> {
        let self = process.new_subject()
        let next_id = case initial_targets {
          [] -> 1
          _ ->
            list.fold(initial_targets, 0, fn(max, target) {
              int.max(max, target.id)
            })
            + 1
        }
        let state =
          State(
            next_id:,
            targets: initial_targets,
            db:,
            check: CheckState(checking: False, rerun: False),
            interval_seconds: settings.check_interval_seconds,
            interval_unit: settings.check_interval_unit,
            interval_generation: 0,
          )
        schedule_tick(self, state)
        process.send(ready, Ok(self))
        loop(self, state, settings_path)
      }
    }
  })
  process.receive_forever(ready)
}

fn data_directory() -> String {
  case simplifile.current_directory() {
    Ok(dir) -> filepath.join(dir, "data")
    Error(_) -> "data"
  }
}

fn schedule_tick(self: Subject(Msg), state: State) -> Nil {
  process.send_after(
    self,
    state.interval_seconds * 1000,
    Tick(state.interval_generation),
  )
  Nil
}

fn loop(self: Subject(Msg), state: State, settings_path: String) -> Nil {
  case process.receive_forever(self) {
    Add(url, reply) -> {
      let #(state, added) = add_target(self, settings_path, state, url)
      process.send(reply, added)
      let state = case added {
        Ok(_) -> begin_check(self, state).0
        Error(_) -> state
      }
      loop(self, state, settings_path)
    }
    Delete(id, reply) -> {
      let #(state, removed) = delete_target(self, settings_path, state, id)
      process.send(reply, removed)
      loop(self, state, settings_path)
    }
    Snapshot(reply) -> {
      process.send(reply, #(
        state.targets,
        latest_results(state.db),
        state.check.checking,
      ))
      loop(self, state, settings_path)
    }
    StartCheck(reply) -> {
      let #(state, start) = begin_check(self, state)
      process.send(reply, start)
      loop(self, state, settings_path)
    }
    GetSettings(reply) -> {
      process.send(reply, current_settings(state))
      loop(self, state, settings_path)
    }
    SetSettings(seconds, unit, reply) -> {
      let settings = normalize_settings(seconds, unit)
      case save_settings(settings_path, settings, state.targets) {
        Error(reason) -> {
          process.send(reply, Error(reason))
          loop(self, state, settings_path)
        }
        Ok(_) -> {
          let state =
            State(
              ..state,
              interval_seconds: settings.check_interval_seconds,
              interval_unit: settings.check_interval_unit,
              interval_generation: state.interval_generation + 1,
            )
          schedule_tick(self, state)
          process.send(reply, Ok(settings))
          loop(self, state, settings_path)
        }
      }
    }
    CheckDone(rows) -> {
      let rows =
        list.filter(rows, fn(row) {
          list.any(state.targets, fn(target) { target.url == row.url })
        })
      case save_results(state.db, rows) {
        Ok(_) -> Nil
        Error(reason) -> io.println("履歴の保存に失敗しました: " <> reason)
      }
      let #(check, run_again) = finish_check(state.check)
      let state = State(..state, check:)
      let state = case run_again {
        True -> begin_check(self, state).0
        False -> state
      }
      loop(self, state, settings_path)
    }
    Tick(generation) -> {
      case generation == state.interval_generation {
        False -> loop(self, state, settings_path)
        True -> {
          schedule_tick(self, state)
          loop(self, begin_check(self, state).0, settings_path)
        }
      }
    }
  }
}

fn current_settings(state: State) -> Settings {
  Settings(
    check_interval_seconds: state.interval_seconds,
    check_interval_unit: state.interval_unit,
  )
}

fn add_target(
  _self: Subject(Msg),
  settings_path: String,
  state: State,
  url: String,
) -> #(State, Result(Target, String)) {
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
              let _ =
                save_settings(
                  settings_path,
                  current_settings(state),
                  state.targets,
                )
              #(state, Ok(target))
            }
          }
        }
      }
    }
  }
}

fn delete_target(
  _self: Subject(Msg),
  settings_path: String,
  state: State,
  id: Int,
) -> #(State, Bool) {
  case list.find(state.targets, fn(target) { target.id == id }) {
    Error(_) -> #(state, False)
    Ok(target) -> {
      let _ = check_history.delete_url(state.db, target.url)
      let state =
        State(
          ..state,
          targets: list.filter(state.targets, fn(item) { item.id != id }),
        )
      let _ =
        save_settings(settings_path, current_settings(state), state.targets)
      #(state, True)
    }
  }
}

// チェックを依頼する。チェック中でなければ、登録全件のチェックを別プロセスで始める。
// チェック中なら、今の1周のあとにもう1周する印だけ付ける。どちらもすぐ返る。
fn begin_check(self: Subject(Msg), state: State) -> #(State, CheckStart) {
  let #(check, start) = request_check(state.check, list.length(state.targets))
  case start {
    Started -> {
      let targets = state.targets
      process.spawn_unlinked(fn() {
        process.send(self, CheckDone(check_all(targets)))
      })
      Nil
    }
    Queued | NoTargets -> Nil
  }
  #(State(..state, check:), start)
}

fn check_all(targets: List(Target)) -> List(ResultRow) {
  targets
  |> list.sized_chunk(browser_slots)
  |> list.flat_map(check_chunk)
}

fn check_chunk(targets: List(Target)) -> List(ResultRow) {
  let incoming = process.new_subject()
  list.each(targets, fn(target) {
    process.spawn_unlinked(fn() {
      let #(outcome, detail) = beam_watch.check_detailed(target.url, 1)
      process.send(incoming, row_for(target.url, outcome, detail))
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
      case process.receive(incoming, within: browser_result_wait_ms) {
        Ok(row) -> collect(incoming, remaining - 1, [row, ..rows])
        Error(_) -> rows
      }
    }
  }
}

fn row_for(
  url: String,
  outcome: beam_watch.Outcome,
  detail: String,
) -> ResultRow {
  let timestamp = now_iso8601()
  let status = case outcome {
    beam_watch.Healthy(_) -> "OK"
    beam_watch.HttpFailure(_) -> "NG"
    beam_watch.Unreachable -> "NG"
  }
  ResultRow(url:, status:, http_status: None, detail:, timestamp:)
}

fn save_results(db: Connection, rows: List(ResultRow)) -> Result(Nil, String) {
  check_history.insert_checks(
    db,
    list.map(rows, fn(row) {
      check_history.CheckRecord(
        url: row.url,
        checked_at: row.timestamp,
        result: row.status,
        detail: row.detail,
      )
    }),
  )
}

fn latest_results(db: Connection) -> List(ResultRow) {
  case check_history.latest(db) {
    Error(reason) -> {
      io.println("履歴の読み込みに失敗しました: " <> reason)
      []
    }
    Ok(records) ->
      list.map(records, fn(record) {
        ResultRow(
          url: record.url,
          status: record.result,
          http_status: None,
          detail: record.detail,
          timestamp: record.checked_at,
        )
      })
  }
}

@external(erlang, "gui_server_ffi", "now_iso8601")
fn now_iso8601() -> String

@external(erlang, "gui_server_ffi", "getenv")
fn getenv(name: String) -> Result(String, Nil)

@external(erlang, "gui_server_ffi", "hostname")
fn hostname() -> String

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
    http.Get, ["targets"] ->
      json_ok(
        encode_targets(
          snapshot(context).0,
          portal.load(context.portal_dir),
          context.hosts,
        ),
        200,
      )
    http.Get, ["results"] -> {
      let #(_, rows, checking) = snapshot(context)
      json_ok(encode_results(rows, checking), 200)
    }
    http.Post, ["targets"] -> add_from_request(request, context)
    http.Delete, ["targets", id] -> delete_from_request(context, id)
    http.Post, ["check"] -> check_now(context)
    http.Get, ["settings"] ->
      json_ok(encode_settings(get_settings(context)), 200)
    http.Post, ["settings"] -> update_settings(request, context)
    _, _ -> json_error("見つかりません", 404)
  }
}

fn snapshot(context: Context) -> #(List(Target), List(ResultRow), Bool) {
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

fn get_settings(context: Context) -> Settings {
  process.call(context.store, waiting: check_wait_ms, sending: GetSettings)
}

fn update_settings(request: Request, context: Context) -> Response {
  use body <- wisp.require_json(request)
  case decode.run(body, settings_decoder()) {
    Error(_) -> json_error("確認間隔が不正です", 400)
    Ok(Settings(seconds, unit)) -> {
      let saved =
        process.call(context.store, waiting: check_wait_ms, sending: fn(reply) {
          SetSettings(seconds, unit, reply)
        })
      case saved {
        Ok(settings) -> json_ok(encode_settings(settings), 200)
        Error(message) -> json_error(message, 500)
      }
    }
  }
}

fn settings_decoder() -> decode.Decoder(Settings) {
  use seconds <- decode.field("checkIntervalSeconds", decode.int)
  use unit <- decode.field("checkIntervalUnit", decode.string)
  decode.success(Settings(
    check_interval_seconds: seconds,
    check_interval_unit: unit,
  ))
}

fn check_now(context: Context) -> Response {
  // チェックの終わりは待たない。受け付けたかどうかだけ返す。
  let start =
    process.call(context.store, waiting: check_wait_ms, sending: StartCheck)
  let #(status, code) = case start {
    Started -> #("started", 202)
    Queued -> #("queued", 202)
    NoTargets -> #("no_targets", 200)
  }
  json_ok(
    json.object([#("ok", json.bool(True)), #("status", json.string(status))]),
    code,
  )
}

fn url_decoder() -> decode.Decoder(String) {
  use url <- decode.field("url", decode.string)
  decode.success(url)
}

fn encode_targets(
  targets: List(Target),
  loaded: portal.Portal,
  hosts: List(String),
) -> json.Json {
  json.object([
    #(
      "targets",
      json.array(targets, fn(target) {
        let info = portal.info_for(loaded, target.url, hosts)
        json.object([
          #("id", json.int(target.id)),
          #("url", json.string(target.url)),
          #(
            "alias",
            json.nullable(option.map(info, fn(i) { i.alias }), json.string),
          ),
          #(
            "app",
            json.nullable(option.then(info, fn(i) { i.app }), json.string),
          ),
          #(
            "destination",
            json.nullable(
              option.map(info, fn(i) { i.destination }),
              json.string,
            ),
          ),
        ])
      }),
    ),
  ])
}

fn encode_target(target: Target) -> json.Json {
  json.object([
    #("id", json.int(target.id)),
    #("url", json.string(target.url)),
  ])
}

fn encode_settings(settings: Settings) -> json.Json {
  json.object([
    #("checkIntervalSeconds", json.int(settings.check_interval_seconds)),
    #("checkIntervalUnit", json.string(settings.check_interval_unit)),
  ])
}

fn encode_results(rows: List(ResultRow), checking: Bool) -> json.Json {
  json.object([
    #("results", json.array(rows, encode_result)),
    #("checking", json.bool(checking)),
  ])
}

fn encode_result(row: ResultRow) -> json.Json {
  json.object([
    #("url", json.string(row.url)),
    #("status", json.string(row.status)),
    #("http_status", json.nullable(row.http_status, json.int)),
    #("detail", json.string(row.detail)),
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
