import gleam/io
import gui_server

pub fn main() {
  io.println("GUIサーバーを起動中...")
  gui_server.start_server()
}