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

pub fn page_missing_formats_as_ng_test() {
  beam_watch.format_outcome(
    "https://example.com",
    beam_watch.Unreachable,
    "ページが出なかった",
  )
  |> should.equal("NG  https://example.com (ページが出なかった)")
}
