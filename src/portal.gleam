//// AI195417 のポータル（nginx、80番）にあるエイリアスを読む。
//// エイリアスと転送先は nginx.conf、アプリ名は html/index.html のカードから取る。

import filepath
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri
import simplifile

/// nginx.conf の1行分。destination は `http://$host:3000/` のように `$host` を含んだまま持つ。
pub type Alias {
  Alias(name: String, destination: String)
}

/// 監視対象の URL に対応するエイリアスの情報。
pub type Info {
  Info(alias: String, app: Option(String), destination: String)
}

pub type Portal {
  Portal(aliases: List(Alias), apps: List(#(String, String)))
}

/// `dir` の nginx.conf と html/index.html を読む。無いファイルは空として扱う。
pub fn load(dir: String) -> Portal {
  let conf =
    simplifile.read(from: filepath.join(dir, "nginx.conf"))
    |> result.unwrap("")
  let html =
    simplifile.read(from: filepath.join(dir, "html/index.html"))
    |> result.unwrap("")
  Portal(aliases: parse_aliases(conf), apps: parse_apps(html))
}

/// `location ~* ^/myerp(?:/(.*))?$ { return 302 http://$host:3000/$1$is_args$args; }` の形の行を読む。
pub fn parse_aliases(conf: String) -> List(Alias) {
  conf
  |> string.split("\n")
  |> list.filter_map(parse_alias_line)
}

fn parse_alias_line(line: String) -> Result(Alias, Nil) {
  let line = string.trim(line)
  use rest <- result.try(case string.starts_with(line, "location ~* ^/") {
    True -> Ok(string.drop_start(line, string.length("location ~* ^/")))
    False -> Error(Nil)
  })
  use #(name, rest) <- result.try(string.split_once(rest, "("))
  use #(_, rest) <- result.try(string.split_once(rest, "return 302 "))
  use #(destination, _) <- result.try(string.split_once(rest, "$1"))
  let name = string.lowercase(string.trim(name))
  let destination = string.trim(destination)
  case name, destination {
    "", _ | _, "" -> Error(Nil)
    _, _ -> Ok(Alias(name:, destination:))
  }
}

/// `<a class="card" href="/myerp"> <div class="card-title">myERP</div>` の形のカードを読む。
/// 戻り値は #(エイリアス名, アプリ名)。
pub fn parse_apps(html: String) -> List(#(String, String)) {
  html
  |> string.split("<a class=\"card\" href=\"")
  |> list.drop(1)
  |> list.filter_map(fn(chunk) {
    use #(href, rest) <- result.try(string.split_once(chunk, "\""))
    use #(_, rest) <- result.try(string.split_once(
      rest,
      "class=\"card-title\">",
    ))
    use #(title, _) <- result.try(string.split_once(rest, "</div>"))
    let name = href |> trim_slashes |> string.lowercase
    case name, string.trim(title) {
      "", _ | _, "" -> Error(Nil)
      _, title -> Ok(#(name, unescape(title)))
    }
  })
}

/// 監視対象の URL が、このサーバーのポータルのエイリアスなら、その情報を返す。
/// `hosts` はこのサーバーを指すホスト名（小文字）。
pub fn info_for(
  portal: Portal,
  url: String,
  hosts: List(String),
) -> Option(Info) {
  case uri.parse(url) {
    Error(_) -> None
    Ok(parsed) -> {
      let host = parsed.host |> option.unwrap("") |> string.lowercase
      let scheme = parsed.scheme |> option.unwrap("") |> string.lowercase
      let on_portal =
        scheme == "http"
        && { parsed.port == None || parsed.port == Some(80) }
        && is_this_server(host, hosts)
      case on_portal, uri.path_segments(parsed.path) {
        True, [first, ..] -> {
          let name = string.lowercase(first)
          case list.find(portal.aliases, fn(alias) { alias.name == name }) {
            Error(_) -> None
            Ok(alias) ->
              Some(Info(
                alias: "/" <> alias.name,
                app: list.key_find(portal.apps, alias.name)
                  |> option.from_result,
                destination: string.replace(alias.destination, "$host", host),
              ))
          }
        }
        _, _ -> None
      }
    }
  }
}

fn is_this_server(host: String, hosts: List(String)) -> Bool {
  host != ""
  && list.any(hosts, fn(name) {
    host == name || string.starts_with(host, name <> ".")
  })
}

fn trim_slashes(text: String) -> String {
  case string.starts_with(text, "/") {
    True -> trim_slashes(string.drop_start(text, 1))
    False ->
      case string.ends_with(text, "/") {
        True -> trim_slashes(string.drop_end(text, 1))
        False -> text
      }
  }
}

fn unescape(text: String) -> String {
  text
  |> string.replace("&lt;", "<")
  |> string.replace("&gt;", ">")
  |> string.replace("&quot;", "\"")
  |> string.replace("&#39;", "'")
  |> string.replace("&amp;", "&")
}
