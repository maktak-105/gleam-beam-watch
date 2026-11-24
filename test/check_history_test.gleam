import check_history
import gleam/int
import gleam/list
import gleeunit
import gleeunit/should
import simplifile

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn history_returns_latest_row_for_every_url_test() {
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
        detail: "",
      )
    })

  let assert Ok(_) = check_history.insert_checks(db, records)
  let assert Ok(_) =
    check_history.insert_checks(db, [
      check_history.CheckRecord(
        url: "https://example.com/1",
        checked_at: "2026-10-01T12:01:00",
        result: "NG",
        detail: "ブラウザで表示できた",
      ),
    ])
  let assert Ok(latest) = check_history.latest(db)
  list.length(latest) |> should.equal(12)
  list.find(latest, fn(record) { record.url == "https://example.com/1" })
  |> should.be_ok
  |> should.equal(check_history.CheckRecord(
    url: "https://example.com/1",
    checked_at: "2026-10-01T12:01:00",
    result: "NG",
    detail: "ブラウザで表示できた",
  ))
  list.first(latest)
  |> should.be_ok
  |> should.equal(check_history.CheckRecord(
    url: "https://example.com/1",
    checked_at: "2026-10-01T12:01:00",
    result: "NG",
    detail: "ブラウザで表示できた",
  ))

  let assert Ok(_) = check_history.delete_url(db, "https://example.com/12")
  let assert Ok(after_delete) = check_history.latest(db)
  list.any(after_delete, fn(record) { record.url == "https://example.com/12" })
  |> should.be_false
}
