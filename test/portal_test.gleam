import gleam/option.{None, Some}
import gleeunit/should
import portal

// AI195417 の C:\server\Apps\portal\nginx.conf と同じ書式（2026-11-25 時点の抜粋）。
const conf = "
        location = / {
            try_files /index.html =404;
        }
        location = /favicon.ico { access_log off; log_not_found off; return 204; }
        location ~* ^/myerp(?:/(.*))?$      { return 302 http://$host:3000/$1$is_args$args; }
        location ~* ^/plan-go(?:/(.*))?$    { return 302 http://$host:8005/$1$is_args$args; }
        location ~* ^/plan(?:/(.*))?$       { return 302 http://$host:8004/$1$is_args$args; }
        location ~* ^/jinji-http(?:/(.*))?$ { return 302 http://$host:8765/$1$is_args$args; }
        location ~* ^/jinji(?:/(.*))?$      { return 302 https://$host:8766/$1$is_args$args; }
        location / {
            return 404;
        }
"

// 同じく html/index.html のカード部分。
const html = "
      <a class=\"card\" href=\"/myerp\">
        <div class=\"card-title\">myERP</div>
        <div class=\"card-desc\">ERP Web アプリ</div>
        <div class=\"card-meta\"><span>/myerp</span><span>:3000</span></div>
      </a>
      <a class=\"card\" href=\"/plan-go\">
        <div class=\"card-title\">生産計画 (Go版)</div>
      </a>
      <a class=\"card\" href=\"/jinji\">
        <div class=\"card-title\">人事DB (HTTPS)</div>
      </a>
"

const hosts = ["ai195417", "localhost", "127.0.0.1"]

fn sample() -> portal.Portal {
  portal.Portal(
    aliases: portal.parse_aliases(conf),
    apps: portal.parse_apps(html),
  )
}

pub fn parse_aliases_reads_redirect_lines_only_test() {
  portal.parse_aliases(conf)
  |> should.equal([
    portal.Alias("myerp", "http://$host:3000/"),
    portal.Alias("plan-go", "http://$host:8005/"),
    portal.Alias("plan", "http://$host:8004/"),
    portal.Alias("jinji-http", "http://$host:8765/"),
    portal.Alias("jinji", "https://$host:8766/"),
  ])
}

pub fn parse_apps_reads_card_titles_test() {
  portal.parse_apps(html)
  |> should.equal([
    #("myerp", "myERP"),
    #("plan-go", "生産計画 (Go版)"),
    #("jinji", "人事DB (HTTPS)"),
  ])
}

pub fn info_for_alias_url_test() {
  portal.info_for(sample(), "http://ai195417/myerp", hosts)
  |> should.equal(
    Some(portal.Info(
      alias: "/myerp",
      app: Some("myERP"),
      destination: "http://ai195417:3000/",
    )),
  )
}

pub fn info_for_keeps_similar_aliases_apart_test() {
  portal.info_for(sample(), "http://ai195417/plan", hosts)
  |> should.equal(
    Some(portal.Info(
      alias: "/plan",
      app: None,
      destination: "http://ai195417:8004/",
    )),
  )
  portal.info_for(sample(), "http://AI195417/Plan-Go/", hosts)
  |> should.equal(
    Some(portal.Info(
      alias: "/plan-go",
      app: Some("生産計画 (Go版)"),
      destination: "http://ai195417:8005/",
    )),
  )
  portal.info_for(sample(), "http://ai195417/jinji", hosts)
  |> should.equal(
    Some(portal.Info(
      alias: "/jinji",
      app: Some("人事DB (HTTPS)"),
      destination: "https://ai195417:8766/",
    )),
  )
}

pub fn info_for_other_urls_is_none_test() {
  portal.info_for(sample(), "http://127.0.0.1:3000/", hosts)
  |> should.equal(None)
  portal.info_for(sample(), "http://other-server/myerp", hosts)
  |> should.equal(None)
  portal.info_for(sample(), "http://ai195417/unknown", hosts)
  |> should.equal(None)
  portal.info_for(sample(), "https://ai195417/myerp", hosts)
  |> should.equal(None)
}

pub fn load_missing_directory_is_empty_test() {
  portal.load("build/no-such-portal")
  |> should.equal(portal.Portal(aliases: [], apps: []))
}
