import beam_watch
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn page_opened_formats_as_ok_test() {
  beam_watch.format_outcome(
    "https://example.com",
    beam_watch.Healthy(200),
    "ページが出た",
  )
  |> should.equal("OK  https://example.com (ページが出た)")
}

// BrowserCheck.ps1 の実際の出力の形（CRLF 付き、日本語、空）を、結果と理由にできること。
pub fn script_output_ok_with_crlf_test() {
  beam_watch.report_from_output("OK\r\n")
  |> should.equal(#(beam_watch.Healthy(200), "ページが出た"))
}

pub fn script_output_ng_reason_test() {
  beam_watch.report_from_output(
    "NG 接続を拒否された (ERR_CONNECTION_REFUSED)\r\nextra line\r\n",
  )
  |> should.equal(#(beam_watch.Unreachable, "接続を拒否された (ERR_CONNECTION_REFUSED)"))
}

pub fn script_output_empty_test() {
  beam_watch.report_from_output("")
  |> should.equal(#(beam_watch.Unreachable, "ページが出なかった"))
}

pub fn page_missing_formats_as_ng_test() {
  beam_watch.format_outcome(
    "https://example.com",
    beam_watch.Unreachable,
    "ページが出なかった",
  )
  |> should.equal("NG  https://example.com (ページが出なかった)")
}
