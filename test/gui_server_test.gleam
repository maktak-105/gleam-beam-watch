import gleeunit/should
import gui_server.{CheckState, NoTargets, Queued, Started}

const idle = CheckState(checking: False, rerun: False)

pub fn request_when_idle_starts_test() {
  gui_server.request_check(idle, 9)
  |> should.equal(#(CheckState(checking: True, rerun: False), Started))
}

pub fn request_without_targets_does_nothing_test() {
  gui_server.request_check(idle, 0)
  |> should.equal(#(idle, NoTargets))
}

// チェック中に何回依頼されても、今の1周のあとに1周だけ追加する。
pub fn requests_while_checking_queue_one_more_round_test() {
  let #(running, _) = gui_server.request_check(idle, 9)
  let #(queued, first) = gui_server.request_check(running, 9)
  let #(queued_again, second) = gui_server.request_check(queued, 9)
  first |> should.equal(Queued)
  second |> should.equal(Queued)
  queued_again |> should.equal(CheckState(checking: True, rerun: True))

  gui_server.finish_check(queued_again)
  |> should.equal(#(idle, True))
}

pub fn finish_without_queue_stops_test() {
  let #(running, _) = gui_server.request_check(idle, 9)
  gui_server.finish_check(running)
  |> should.equal(#(idle, False))
}
