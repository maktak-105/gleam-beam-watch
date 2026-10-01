import filepath
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import simplifile
import sqlight.{type Connection}

const kept_rows = 10_000

const shown_rows = 10

pub type CheckRecord {
  CheckRecord(url: String, checked_at: String, result: String)
}

pub fn open(directory: String) -> Result(Connection, String) {
  case simplifile.create_directory_all(directory) {
    Error(err) -> Error("履歴フォルダを作れません: " <> string.inspect(err))
    Ok(_) -> {
      let path = filepath.join(directory, "history.sqlite3")
      case sqlight.open(path) {
        Error(err) -> Error("履歴DBを開けません: " <> string.inspect(err))
        Ok(db) -> {
          case sqlight.exec(create_sql, on: db) {
            Ok(_) -> Ok(db)
            Error(err) -> Error("履歴テーブルを作れません: " <> string.inspect(err))
          }
        }
      }
    }
  }
}

pub fn insert_checks(
  db: Connection,
  records: List(CheckRecord),
) -> Result(Nil, String) {
  case records {
    [] -> Ok(Nil)
    _ -> {
      use _ <- result.try(statement("begin immediate", db))
      let inserted = list.try_each(records, insert_one(db, _))
      case inserted {
        Error(reason) -> {
          let _ = statement("rollback", db)
          Error(reason)
        }
        Ok(_) -> {
          use _ <- result.try(prune(db))
          statement("commit", db)
        }
      }
    }
  }
}

pub fn latest(db: Connection) -> Result(List(CheckRecord), String) {
  let sql =
    "select url, checked_at, result from checks order by id desc limit "
    <> int.to_string(shown_rows)
  sqlight.query(sql, on: db, with: [], expecting: record_decoder())
  |> map_error
}

pub fn delete_url(db: Connection, url: String) -> Result(Nil, String) {
  sqlight.query(
    "delete from checks where url = ?",
    on: db,
    with: [sqlight.text(url)],
    expecting: decode.success(Nil),
  )
  |> map_error
  |> result.replace(Nil)
}

fn insert_one(db: Connection, record: CheckRecord) -> Result(Nil, String) {
  sqlight.query(
    "insert into checks (url, checked_at, result) values (?, ?, ?)",
    on: db,
    with: [
      sqlight.text(record.url),
      sqlight.text(record.checked_at),
      sqlight.text(record.result),
    ],
    expecting: decode.success(Nil),
  )
  |> map_error
  |> result.replace(Nil)
}

fn prune(db: Connection) -> Result(Nil, String) {
  let sql =
    "delete from checks where id not in ("
    <> "select id from checks order by id desc limit "
    <> int.to_string(kept_rows)
    <> ")"
  statement(sql, db)
}

fn statement(sql: String, db: Connection) -> Result(Nil, String) {
  sqlight.exec(sql, on: db)
  |> map_error
}

fn record_decoder() -> decode.Decoder(CheckRecord) {
  use url <- decode.field(0, decode.string)
  use checked_at <- decode.field(1, decode.string)
  use result <- decode.field(2, decode.string)
  decode.success(CheckRecord(url:, checked_at:, result:))
}

fn map_error(value: Result(a, sqlight.Error)) -> Result(a, String) {
  result.map_error(value, string.inspect)
}

const create_sql = "
create table if not exists checks (
  id integer primary key autoincrement,
  url text not null,
  checked_at text not null,
  result text not null
)
"
