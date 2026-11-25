-module(beam_watch_ffi).

-export([safe_dispatch/2, browser_check/1, first_line/1]).

safe_dispatch(Configuration, Request) ->
    try gleam@httpc:dispatch(Configuration, Request) of
        {ok, Response} -> {ok, Response};
        {error, _} -> {error, nil}
    catch
        _:_ -> {error, nil}
    end.

browser_check(Url) ->
    UrlString = case Url of
        Bin when is_binary(Bin) -> binary_to_list(Bin);
        List when is_list(List) -> List
    end,
    case find_script() of
        {ok, Script} -> run_browser(Script, UrlString);
        error -> <<"NG 確認スクリプトがない"/utf8>>
    end.

find_script() ->
    Candidates = [
        "deploy/BrowserCheck.ps1",
        "deploy/server/BrowserCheck.ps1"
    ],
    case [filename:absname(Path) || Path <- Candidates, filelib:is_file(Path)] of
        [Path | _] -> {ok, Path};
        [] -> error
    end.

run_browser(Script, Url) ->
    case find_pwsh() of
        error -> <<"NG PowerShellがない"/utf8>>;
        Pwsh ->
            Args = [
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                Script,
                "-Url",
                Url
            ],
            Port = open_port(
                {spawn_executable, Pwsh},
                [binary, exit_status, hide, stderr_to_stdout, {args, Args}]
            ),
            collect_port(Port, <<>>, 45000)
    end.

find_pwsh() ->
    Candidates = [
        "C:/Program Files/PowerShell/7/pwsh.exe",
        "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
    ],
    case [Path || Path <- Candidates, filelib:is_file(Path)] of
        [Path | _] -> Path;
        [] ->
            case os:find_executable("powershell") of
                false -> error;
                Path -> Path
            end
    end.

collect_port(Port, Acc, Timeout) ->
    receive
        {Port, {data, Data}} ->
            collect_port(Port, <<Acc/binary, Data/binary>>, Timeout);
        {Port, {exit_status, _}} ->
            Acc
    after Timeout ->
        _ = try port_close(Port) catch _:_ -> ok end,
        <<Acc/binary, "\nNG タイムアウト"/utf8>>
    end.

%% ブラウザ判定スクリプトの出力から、最初の1行を UTF-8 binary で返す。
first_line(Output) ->
    Utf8 = case unicode:characters_to_binary(Output, utf8, utf8) of
        Bin when is_binary(Bin) -> Bin;
        _ -> <<"NG ページを取得できない"/utf8>>
    end,
    Trimmed = string:trim(Utf8),
    case binary:split(Trimmed, <<"\n">>) of
        %% string:trim/3 の第3引数は文字のリスト。binary を渡すと function_clause で落ちる。
        [Head | _] -> unicode:characters_to_binary(string:trim(Head, trailing, "\r"));
        _ -> <<"NG ページを取得できない"/utf8>>
    end.
