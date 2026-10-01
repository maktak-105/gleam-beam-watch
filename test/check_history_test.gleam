import check_history
import gleam/int
import gleam/list
import gleeunit
import gleeunit/should
import simplifile

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn history_keeps_three_fields_and_returns_newest_ten_test() {
  let dir = "build/history-test"
  let _ = simplifile.delete("build/history-test/history.sqlite3")
  let assert Ok(db) = check_history.open(dir)

  let records =
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
    |> list.map(fn(n) {
      check_history.CheckRecord(
        url: "https://example.com/" <> int.to_string(n),
        checked_at: "2026-10-01T12:00:" <> int.to_string(n),
        result: "OK",
      )
    })

  let assert Ok(_) = check_history.insert_checks(db, records)
  let assert Ok(latest) = check_history.latest(db)
  list.length(latest) |> should.equal(10)
  list.first(latest)
  |> should.be_ok
  |> should.equal(check_history.CheckRecord(
    url: "https://example.com/12",
    checked_at: "2026-10-01T12:00:12",
    result: "OK",
  ))

  let assert Ok(_) = check_history.delete_url(db, "https://example.com/12")
  let assert Ok(after_delete) = check_history.latest(db)
  list.any(after_delete, fn(record) { record.url == "https://example.com/12" })
  |> should.be_false
}
