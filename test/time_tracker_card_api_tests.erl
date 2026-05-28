-module(time_tracker_card_api_tests).

-include_lib("eunit/include/eunit.hrl").

-define(CARD, <<"11111111-1111-1111-1111-111111111111">>).
-define(USER, 7).

card_api_test_() ->
    {foreach,
     fun() -> meck:new(time_tracker_db, [non_strict]) end,
     fun(_) -> meck:unload(time_tracker_db) end,
     [
        fun touch_first_of_day_is_arrival/0,
        fun touch_second_of_day_is_leave/0,
        fun touch_after_close_returns_already_closed/0,
        fun touch_unknown_card_returns_db_error/0,
        fun assign_returns_card_and_user/0,
        fun assign_duplicate_returns_already_assigned/0,
        fun delete_returns_user/0,
        fun delete_missing_returns_already_deleted/0,
        fun list_by_user_returns_card_uids/0,
        fun delete_all_by_user_returns_removed_uids/0
     ]}.

%% touch
touch_first_of_day_is_arrival() ->
    expect_touch({ok, 1, columns, [{true}]}),
    ?assertEqual(
       {ok, #{<<"card_uid">> => ?CARD, <<"user_id">> => ?USER, <<"event_type">> => <<"arrival">>}},
       time_tracker_card_api:touch(#{<<"card_uid">> => ?CARD})).

touch_second_of_day_is_leave() ->
    expect_touch({ok, 1, columns, [{false}]}),
    ?assertEqual(
       {ok, #{<<"card_uid">> => ?CARD, <<"user_id">> => ?USER, <<"event_type">> => <<"leave">>}},
       time_tracker_card_api:touch(#{<<"card_uid">> => ?CARD})).

touch_after_close_returns_already_closed() ->
    expect_touch({ok, 0, columns, []}),
    ?assertEqual({error, already_closed},
                 time_tracker_card_api:touch(#{<<"card_uid">> => ?CARD})).

touch_unknown_card_returns_db_error() ->
    %% GET_CARD_USER returns no rows -> touch never runs -> db_error
    meck:expect(time_tracker_db, query,
                fun(_Q, P) when length(P) =:= 1 -> {ok, columns, []} end),
    ?assertEqual({error, db_error},
                 time_tracker_card_api:touch(#{<<"card_uid">> => ?CARD})).

%% assign
assign_returns_card_and_user() ->
    expect_query({ok, 1}),
    ?assertEqual(
       {ok, #{<<"card_uid">> => ?CARD, <<"user_id">> => ?USER}},
       time_tracker_card_api:assign(#{<<"card_uid">> => ?CARD, <<"user_id">> => ?USER})).

assign_duplicate_returns_already_assigned() ->
    expect_query({error, {error, error, <<"23505">>, unique_violation, <<"dup">>, []}}),
    ?assertEqual({error, already_assigned},
                 time_tracker_card_api:assign(#{<<"card_uid">> => ?CARD, <<"user_id">> => ?USER})).

%% delete
delete_returns_user() ->
    expect_query({ok, 1, columns, [{?USER}]}),
    ?assertEqual(
       {ok, #{<<"card_uid">> => ?CARD, <<"user_id">> => ?USER}},
       time_tracker_card_api:delete(#{<<"card_uid">> => ?CARD})).

delete_missing_returns_already_deleted() ->
    expect_query({ok, 0, columns, []}),
    ?assertEqual({error, already_deleted},
                 time_tracker_card_api:delete(#{<<"card_uid">> => ?CARD})).

%% list / delete_all
list_by_user_returns_card_uids() ->
    expect_query({ok, columns, [{?CARD}, {<<"22222222-2222-2222-2222-222222222222">>}]}),
    ?assertEqual(
       {ok, #{<<"user_id">> => ?USER,
              <<"card_uids">> => [?CARD, <<"22222222-2222-2222-2222-222222222222">>]}},
       time_tracker_card_api:list_by_user(#{<<"user_id">> => ?USER})).

delete_all_by_user_returns_removed_uids() ->
    expect_query({ok, 2, columns, [{?CARD}]}),
    ?assertEqual(
       {ok, #{<<"user_id">> => ?USER, <<"card_uids">> => [?CARD]}},
       time_tracker_card_api:delete_all_by_user(#{<<"user_id">> => ?USER})).

%% helpers
expect_query(Return) ->
    meck:expect(time_tracker_db, query, fun(_Query, _Params) -> Return end).

%% touch issues two queries: lookup (1 param) then upsert (3 params)
expect_touch(TouchReturn) ->
    meck:expect(time_tracker_db, query,
                fun(_Q, P) when length(P) =:= 1 -> {ok, columns, [{?USER}]};
                   (_Q, P) when length(P) =:= 3 -> TouchReturn
                end).
