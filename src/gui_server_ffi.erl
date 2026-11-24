-module(gui_server_ffi).
-export([now_iso8601/0, getenv/1]).

%% ローカル時刻を `YYYY-MM-DDTHH:MM:SS` の UTF-8 binary で返す。
now_iso8601() ->
    {{Year, Month, Day}, {Hour, Minute, Second}} = calendar:local_time(),
    unicode:characters_to_binary(io_lib:format(
        "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B",
        [Year, Month, Day, Hour, Minute, Second]
    )).

%% 環境変数を UTF-8 binary で返す。未設定は {error, nil}。
getenv(Name) when is_binary(Name) ->
    case os:getenv(binary_to_list(Name)) of
        false -> {error, nil};
        Value -> {ok, unicode:characters_to_binary(Value)}
    end.
