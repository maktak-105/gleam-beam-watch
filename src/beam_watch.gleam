import argv
import gleam/erlang/process
import gleam/io
import gleam/list
import gleam/string

const result_wait_timeout_ms = 70_000

pub type Outcome {
  Healthy(status: Int)
  HttpFailure(status: Int)
  Unreachable
}

type CheckResult {
  CheckResult(url: String, outcome: Outcome, detail: String)
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
      let #(outcome, detail) = check_detailed(url, 1)
      process.send(results, CheckResult(url, outcome, detail))
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
        Ok(CheckResult(url, outcome, detail)) -> {
          io.println(format_outcome(url, outcome, detail))
          collect_results(results, remaining - 1)
        }
        Error(_) -> io.println("NG  結果を待っている間にタイムアウトしました")
      }
  }
}

// GUI サーバーなど外部から呼び出すためのチェック関数。
// ブラウザで1回開き、ページが出れば OK を返す。
pub fn check(url: String, remaining: Int) -> Outcome {
  let #(outcome, _detail) = check_detailed(url, remaining)
  outcome
}

// 登録 URL はすべて、ブラウザで1回開いた結果だけを返す。
pub fn check_detailed(url: String, _remaining: Int) -> #(Outcome, String) {
  browser_report(browser_check(url))
}

fn browser_report(line: String) -> #(Outcome, String) {
  let line = string.trim(line)
  case string.starts_with(line, "OK") {
    True -> #(Healthy(200), "ページが出た")
    False -> #(Unreachable, reason_text(line))
  }
}

fn reason_text(line: String) -> String {
  case string.starts_with(line, "NG") {
    True -> blank_as_failed(string.trim(string.drop_start(line, 2)))
    False -> blank_as_failed(line)
  }
}

fn blank_as_failed(line: String) -> String {
  case line {
    "" -> "ページが出なかった"
    _ -> line
  }
}

@external(erlang, "beam_watch_ffi", "browser_check")
fn browser_check(url: String) -> String

pub fn format_outcome(url: String, outcome: Outcome, detail: String) -> String {
  case outcome {
    Healthy(_) -> "OK  " <> url <> " (" <> detail <> ")"
    HttpFailure(_) -> "NG  " <> url <> " (" <> detail <> ")"
    Unreachable -> "NG  " <> url <> " (" <> detail <> ")"
  }
}

fn print_usage() -> Nil {
  io.println("使い方: gleam run -- <URL> [URL ...]")
  io.println("例:     gleam run -- https://gleam.run https://example.invalid")
}
