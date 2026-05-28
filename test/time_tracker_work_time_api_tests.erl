-module(time_tracker_work_time_api_tests).

-include_lib("eunit/include/eunit.hrl").

-define(USER, 7).

work_time_api_test_() ->
    {foreach,
     fun() -> meck:new(time_tracker_db, [non_strict]) end,
     fun(_) -> meck:unload(time_tracker_db) end,
     [
        fun set_returns_ok/0,
        fun get_returns_schedule_with_formatted_time/0,
        fun add_exclusion_echoes_payload/0,
        fun delete_exclusion_returns_ok/0,
        fun get_exclusion_maps_rows/0,
        fun get_exclusion_handles_empty/0,
        fun history_maps_rows_and_formats_time/0,
        fun statistic_computes_deterministic_fields/0
     ]}.

set_returns_ok() ->
    expect_query({ok, 1}),
    Args = #{<<"user_id">> => ?USER, <<"start_time">> => <<"09:00:00">>,
             <<"end_time">> => <<"18:00:00">>, <<"days">> => 5},
    ?assertEqual(ok, time_tracker_work_time_api:set(Args)).

get_returns_schedule_with_formatted_time() ->
    expect_query({ok, columns, [{{9, 0, 0}, {18, 0, 0}, 5}]}),
    ?assertEqual(
       {ok, #{<<"user_id">>    => ?USER,
              <<"start_time">> => <<"09:00:00">>,
              <<"end_time">>   => <<"18:00:00">>,
              <<"days">>       => 5}},
       time_tracker_work_time_api:get(#{<<"user_id">> => ?USER})).

add_exclusion_echoes_payload() ->
    expect_query({ok, 1, columns, [{99}]}),
    Args = #{<<"user_id">>        => ?USER,
             <<"type_exclusion">> => <<"full-time">>,
             <<"start_datetime">> => <<"2026-01-01T00:00:00">>,
             <<"end_datetime">>   => <<"2026-01-05T00:00:00">>},
    ?assertEqual(
       {ok, #{<<"user_id">>  => ?USER,
              <<"exclusion">> => #{
                  <<"id">>             => 99,
                  <<"type_exclusion">> => <<"full-time">>,
                  <<"start_datetime">> => <<"2026-01-01T00:00:00">>,
                  <<"end_datetime">>   => <<"2026-01-05T00:00:00">>}}},
       time_tracker_work_time_api:add_exclusion(Args)).

delete_exclusion_returns_ok() ->
    expect_query({ok, 1}),
    ?assertEqual(ok, time_tracker_work_time_api:delete_exclusion(#{<<"id">> => 99})).

get_exclusion_maps_rows() ->
    Rows = [{99, <<"2026-01-01T00:00:00">>, <<"2026-01-05T00:00:00">>, <<"full-time">>}],
    expect_query({ok, columns, Rows}),
    ?assertEqual(
       {ok, #{<<"user_id">>    => ?USER,
              <<"exclusions">> => [#{
                  <<"id">>             => 99,
                  <<"start_datetime">> => <<"2026-01-01T00:00:00">>,
                  <<"end_datetime">>   => <<"2026-01-05T00:00:00">>,
                  <<"type_exclusion">> => <<"full-time">>}]}},
       time_tracker_work_time_api:get_exclusion(#{<<"user_id">> => ?USER})).

get_exclusion_handles_empty() ->
    expect_query({ok, columns, []}),
    ?assertEqual({ok, #{<<"user_id">> => ?USER, <<"exclusions">> => []}},
                 time_tracker_work_time_api:get_exclusion(#{<<"user_id">> => ?USER})).

history_maps_rows_and_formats_time() ->
    Rows = [{{2026, 1, 15}, {9, 5, 0}, {18, 0, 0}}],
    expect_query({ok, columns, Rows}),
    ?assertEqual(
       {ok, #{<<"user_id">> => ?USER,
              <<"history">> => [#{
                  <<"date">>       => {2026, 1, 15},
                  <<"start_time">> => <<"09:05:00">>,
                  <<"end_time">>   => <<"18:00:00">>}]}},
       time_tracker_work_time_api:history_by_user(#{<<"user_id">> => ?USER})).

statistic_computes_deterministic_fields() ->
    %% query 1 (1 param): reg_date, day_mins, days_at_week
    %% query 2 (3 params): worked_mins, late, late_reason, leave, leave_reason, vacation
    meck:expect(time_tracker_db, query,
                fun(_Q, P) when length(P) =:= 1 -> {ok, columns, [{{2026, 1, 1}, 540, 5}]};
                   (_Q, P) when length(P) =:= 3 -> {ok, columns, [{480, 3, 1, 2, 0, 1}]}
                end),
    {ok, Resp} = time_tracker_work_time_api:statistic_by_user(
                   #{<<"user_id">> => ?USER, <<"filter">> => <<"all_time">>}),
    ?assertEqual(?USER, maps:get(<<"user_id">>, Resp)),
    Stat = maps:get(<<"statistic">>, Resp),

    %% deterministic: counts come straight from the mocked aggregate row
    ?assertEqual(#{<<"without_reason">> => 2, <<"with_reason">> => 1},
                 maps:get(<<"late_count">>, Stat)),
    ?assertEqual(#{<<"without_reason">> => 2, <<"with_reason">> => 0},
                 maps:get(<<"leave_count">>, Stat)),
    ?assertEqual(<<"08:00:00">>, maps:get(<<"worked">>, maps:get(<<"time">>, Stat))),
    ?assertEqual(1, maps:get(<<"leave">>, maps:get(<<"days">>, Stat))),

    %% date-derived fields depend on today's date -> assert presence/type only
    Days = maps:get(<<"days">>, Stat),
    ?assert(is_integer(maps:get(<<"work_days">>, Days))),
    ?assert(is_integer(maps:get(<<"weekends">>, Days))),
    Time = maps:get(<<"time">>, Stat),
    ?assert(is_binary(maps:get(<<"total">>, Time))),
    ?assert(is_binary(maps:get(<<"undertime">>, Time))).

%% helpers
expect_query(Return) ->
    meck:expect(time_tracker_db, query, fun(_Query, _Params) -> Return end).
