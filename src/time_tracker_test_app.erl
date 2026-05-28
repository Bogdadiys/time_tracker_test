-module(time_tracker_test_app).
-behaviour(application).

-include("time_tracker.hrl").

-export([start/0]).
-export([start/2]).
-export([stop/1]).

start() ->
	application:ensure_all_started(time_tracker_test).

start(_Type, _Args) ->
	time_tracker_validator:add_rules(),
    ok = start_handler(),
	time_tracker_test_sup:start_link().

stop(_State) ->
	ok.

start_handler() ->
    {ok, Port} = application:get_env(time_tracker_test, cowboy_port),
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/[...]", time_tracker_http_handler, []}
        ]}
    ]),
    ProtocolOpts = #{
        env => #{dispatch => Dispatch}
    },
    {ok, _} = cowboy:start_clear(http, [{port, Port}], ProtocolOpts),
    ?DEBUG("Cowboy started at port: ~p", [Port]),
    ok.
