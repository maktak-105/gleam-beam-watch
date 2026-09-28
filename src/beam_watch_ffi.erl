-module(beam_watch_ffi).

-export([safe_dispatch/2]).

safe_dispatch(Configuration, Request) ->
    try gleam@httpc:dispatch(Configuration, Request) of
        {ok, Response} -> {ok, Response};
        {error, _} -> {error, nil}
    catch
        _:_ -> {error, nil}
    end.
