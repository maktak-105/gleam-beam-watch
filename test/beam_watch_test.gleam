import beam_watch
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn success_statuses_are_healthy_test() {
  beam_watch.is_healthy_status(200)
  |> should.be_true

  beam_watch.is_healthy_status(399)
  |> should.be_true
}

pub fn error_statuses_are_unhealthy_test() {
  beam_watch.is_healthy_status(199)
  |> should.be_false

  beam_watch.is_healthy_status(400)
  |> should.be_false
}

pub fn outcome_formatting_test() {
  beam_watch.format_outcome("https://example.com", beam_watch.Healthy(200))
  |> should.equal("OK  https://example.com (HTTP 200)")

  beam_watch.format_outcome("https://example.com", beam_watch.HttpFailure(503))
  |> should.equal("NG  https://example.com (HTTP 503)")
}
