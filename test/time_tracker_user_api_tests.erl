-module(time_tracker_user_api_tests).

-include_lib("eunit/include/eunit.hrl").

user_api_test_() ->
    {foreach,
     fun() -> meck:new(time_tracker_db, [non_strict]) end,
     fun(_) -> meck:unload(time_tracker_db) end,
     [
        fun create_returns_new_id/0,
        fun delete_returns_ok/0,
        fun list_maps_rows_and_formats_time/0,
        fun list_handles_empty/0,
        fun list_formats_null_time_as_empty/0
     ]}.

create_returns_new_id() ->
    expect_query({ok, 1, [<<"id">>], [{42}]}),
    ?assertEqual({ok, #{<<"id">> => 42}},
                 time_tracker_user_api:create(#{<<"user_name">> => <<"Bob">>})).

delete_returns_ok() ->
    expect_query({ok, 1}),
    ?assertEqual(ok, time_tracker_user_api:delete(#{<<"user_id">> => 42})).

list_maps_rows_and_formats_time() ->
    Rows = [{1, <<"Bob">>, {9, 0, 0}, {18, 0, 0}}],
    expect_query({ok, columns, Rows}),
    ?assertEqual(
       {ok, [#{<<"user_id">>             => 1,
               <<"name">>                => <<"Bob">>,
               <<"expected_start_time">> => <<"09:00:00">>,
               <<"expected_stop_time">>  => <<"18:00:00">>}]},
       time_tracker_user_api:list(#{})).

list_handles_empty() ->
    expect_query({ok, columns, []}),
    ?assertEqual({ok, []}, time_tracker_user_api:list(#{})).

list_formats_null_time_as_empty() ->
    Rows = [{2, <<"Eve">>, null, null}],
    expect_query({ok, columns, Rows}),
    {ok, [User]} = time_tracker_user_api:list(#{}),
    ?assertEqual(<<"">>, maps:get(<<"expected_start_time">>, User)),
    ?assertEqual(<<"">>, maps:get(<<"expected_stop_time">>, User)).

%% helpers
expect_query(Return) ->
    meck:expect(time_tracker_db, query, fun(_Query, _Params) -> Return end).
