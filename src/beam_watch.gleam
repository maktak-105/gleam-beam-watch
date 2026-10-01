import argv
import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/int
import gleam/io
import gleam/list

const request_timeout_ms = 5000

const retry_count = 3

const retry_wait_ms = 500

const result_wait_timeout_ms = 17_000

pub type Outcome {
  Healthy(status: Int)
  HttpFailure(status: Int)
  Unreachable
}

type CheckResult {
  CheckResult(url: String, outcome: Outcome)
}

pub fn main() -> Nil {
  case argv.load().arguments {
    [] -> print_usage()
    urls -> check_urls(urls)
  }
}

fn check_urls(urls: List(String)) -> Nil {
  let results = process.new_subject()

  urls
  |> list.each(fn(url) {
    process.spawn_unlinked(fn() {
      let outcome = check(url, retry_count)
      process.send(results, CheckResult(url, outcome))
    })
  })

  collect_results(results, list.length(urls))
}

fn collect_results(
  results: process.Subject(CheckResult),
  remaining: Int,
) -> Nil {
  case remaining {
    0 -> Nil
    _ ->
      case process.receive(results, within: result_wait_timeout_ms) {
        Ok(CheckResult(url, outcome)) -> {
          io.println(format_outcome(url, outcome))
          collect_results(results, remaining - 1)
        }
        Error(_) -> io.println("NG  結果を待っている間にタイムアウトしました")
      }
  }
}

// GUI サーバーなど外部から呼び出すためのチェック関数。
// `remaining` 回のリトライを行って最終的な Outcome を返す。
pub fn check(url: String, remaining: Int) -> Outcome {
  let outcome = check_once(url)

  case outcome {
    Healthy(_) -> outcome
    _ if remaining <= 1 -> outcome
    _ -> {
      process.sleep(retry_wait_ms)
      check(url, remaining - 1)
    }
  }
}

fn check_once(url: String) -> Outcome {
  case request.to(url) {
    Error(_) -> Unreachable
    Ok(request) -> {
      let config =
        httpc.configure()
        |> httpc.timeout(request_timeout_ms)
        |> httpc.follow_redirects(True)

      case safe_dispatch(config, request) {
        Ok(response) -> outcome_for_status(response.status)
        Error(_) -> Unreachable
      }
    }
  }
}

pub fn is_healthy_status(status: Int) -> Bool {
  status >= 200 && status < 400
}

fn outcome_for_status(status: Int) -> Outcome {
  case is_healthy_status(status) {
    True -> Healthy(status)
    False -> HttpFailure(status)
  }
}

// The OTP HTTP client can raise an exception while loading a system certificate
// store. Convert such a runtime failure into a regular monitoring failure so a
// worker always reports a result to the main process.
@external(erlang, "beam_watch_ffi", "safe_dispatch")
fn safe_dispatch(
  config: httpc.Configuration,
  request: request.Request(String),
) -> Result(response.Response(String), Nil)

pub fn format_outcome(url: String, outcome: Outcome) -> String {
  case outcome {
    Healthy(status) ->
      "OK  " <> url <> " (HTTP " <> int.to_string(status) <> ")"
    HttpFailure(status) ->
      "NG  " <> url <> " (HTTP " <> int.to_string(status) <> ")"
    Unreachable -> "NG  " <> url <> " (接続失敗または不正な URL)"
  }
}

fn print_usage() -> Nil {
  io.println("使い方: gleam run -- <URL> [URL ...]")
  io.println("例:     gleam run -- https://gleam.run https://example.invalid")
}
