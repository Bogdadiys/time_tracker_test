-module(time_tracker_user_api).

%% API
-export([create/1]).
-export([delete/1]).
-export([list/1]).

-include("time_tracker.hrl").

%% SQL
-define(CREATE_USER_QUERY, "
    INSERT INTO users (name)
    VALUES ($1)
    RETURNING id
").

-define(DELETE_USER_QUERY, "
    DELETE FROM users
    WHERE id = $1
").

-define(GET_USERS_QUERY, "
    SELECT id, name, expected_start_time, expected_stop_time
    FROM users
").

%% API
create(Args) ->
    UserName = maps:get(<<"user_name">>, Args),
    {ok, _, _, [{UserId}]} = time_tracker_db:query(?CREATE_USER_QUERY, [UserName]),
    {ok, #{<<"id">> => UserId}}.

delete(Args) ->
    UserId = maps:get(<<"user_id">>, Args),
    {ok, _} = time_tracker_db:query(?DELETE_USER_QUERY, [UserId]),
    ok.

list(_Args) ->
    {ok, _, Users} = time_tracker_db:query(?GET_USERS_QUERY, []),
    Maps = [
        #{
            <<"user_id">>             => Id,
            <<"expected_start_time">> => time_tracker_utils:time_to_binary(StartTime),
            <<"expected_stop_time">>  => time_tracker_utils:time_to_binary(StopTime),
            <<"name">>                => Name
        }
    || {Id, Name, StartTime, StopTime} <- Users],
    {ok, Maps}.
