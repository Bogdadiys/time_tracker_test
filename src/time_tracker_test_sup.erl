-module(time_tracker_test_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(CHILD(I), #{
	id       => I,
	start    => {I, start_link, []},
	restart  => permanent,
	shutdown => 2000,
	type     => worker,
	modules  => [I]
}).

start_link() ->
	supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
	Procs = [?CHILD(time_tracker_mq_handler)],
	{ok, {{one_for_one, 1, 5}, Procs}}.
