-module(gui_server_ffi).
-export([now_iso8601/0]).

%% ローカル時刻を `YYYY-MM-DDTHH:MM:SS` の UTF-8 binary で返す。
now_iso8601() ->
    {{Year, Month, Day}, {Hour, Minute, Second}} = calendar:local_time(),
    unicode:characters_to_binary(io_lib:format(
        "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B",
        [Year, Month, Day, Hour, Minute, Second]
    )).
