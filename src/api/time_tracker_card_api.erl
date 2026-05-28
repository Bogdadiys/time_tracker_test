-module(time_tracker_card_api).

%% API
-export([touch/1]).
-export([assign/1]).
-export([delete/1]).
-export([list_by_user/1]).
-export([delete_all_by_user/1]).

-include("time_tracker.hrl").

%% SQL
-define(GET_CARD_USER_QUERY, "
    SELECT user_id
    FROM user_cards
    WHERE id = $1
").

-define(TOUCH_CARD_QUERY, "
    INSERT INTO time_log (user_id, date, start_time, is_late, is_late_reason) 
    VALUES ($1, $2, $3, $3 > (SELECT expected_start_time FROM users WHERE id = $1),
        (SELECT COALESCE(
            (SELECT true FROM public.user_exclusions WHERE user_id = $1 AND ((type_exclusion = 'come later') OR (type_exclusion = 'full-time')) AND CURRENT_DATE BETWEEN start_datetime AND stop_datetime),
            false)
        ))
    ON CONFLICT (user_id, date) DO UPDATE SET
        stop_time = $3,
        is_leave = ($3 < (SELECT expected_stop_time FROM users WHERE id = $1)),
        is_leave_reason = (SELECT COALESCE(
            (SELECT true FROM public.user_exclusions WHERE user_id = $1 AND ((type_exclusion = 'leave earlier') OR (type_exclusion = 'full-time')) AND CURRENT_DATE BETWEEN start_datetime AND stop_datetime),
            false
        )),
        total_mins = (select extract(epoch from($3 - time_log.start_time)) / 60)
    WHERE time_log.stop_time IS NULL
    RETURNING (xmax = 0) AS is_arrival
").

-define(ASSIGN_CARD_QUERY, "
    INSERT INTO user_cards (id, user_id)
    VALUES ($1, $2)
").

-define(DELETE_CARD_QUERY, "
    DELETE FROM user_cards
    WHERE id = $1
    RETURNING user_id
").

-define(GET_USER_CARDS_QUERY, "
    SELECT id
    FROM user_cards
    WHERE user_id = $1
").

-define(DELETE_CARDS_BY_USER_QUERY, "
    DELETE FROM user_cards
    WHERE user_id = $1
    RETURNING id
").

%% API
-spec touch(Args :: map()) ->
    {ok, Response :: map()} |
    {error, db_error | already_closed}.
touch(Args) ->
    Date = date(),
    Time = time(),
    CardId = maps:get(<<"card_uid">>, Args),
    case time_tracker_db:query(?GET_CARD_USER_QUERY, [CardId]) of
        {ok, _, [{UserId}]} ->
            case time_tracker_db:query(?TOUCH_CARD_QUERY, [UserId, Date, Time]) of
                {ok, 1, _, [{IsArrival}]} ->
                    EventType = case IsArrival of
                        true -> <<"arrival">>;
                        _ -> <<"leave">>
                    end,
                    {ok, #{<<"card_uid">> => CardId, <<"user_id">> => UserId, <<"event_type">> => EventType}};
                {ok, 0, _, _} ->
                    {error, already_closed};
                Err ->
                    ?ERROR("[time_tracker_card_api] Failed touch request with error: ~p", [Err]),
                    {error, db_error}
            end;
        Err ->
            ?ERROR("[time_tracker_card_api] Failed touch request with error: ~p", [Err]),
            {error, db_error}
    end.

-spec assign(Args :: map()) ->
    {ok, Response :: map()} |
    {error, db_error | already_assigned}.
assign(Args) ->
    UserId = maps:get(<<"user_id">>, Args),
    CardId = maps:get(<<"card_uid">>, Args),
    case time_tracker_db:query(?ASSIGN_CARD_QUERY, [CardId, UserId]) of
        {ok, 1} ->
            {ok, #{<<"card_uid">> => CardId, <<"user_id">> => UserId}};
        {error,{_, _, _, unique_violation, _, _}} ->
            {error, already_assigned};
        Err ->
            ?ERROR("[time_tracker_card_api] Failed assign request with error: ~p", [Err]),
            {error, db_error}
    end.

-spec delete(Args :: map()) ->
    {ok, Response :: map()} |
    {error, db_error | already_deleted}.
delete(Args) ->
    CardId = maps:get(<<"card_uid">>, Args),
    case time_tracker_db:query(?DELETE_CARD_QUERY, [CardId]) of
        {ok, 1, _, [{UserId}]} ->
            {ok, #{<<"card_uid">> => CardId, <<"user_id">> => UserId}};
        {ok, 0, _, _} ->
            {error, already_deleted};
        Err ->
            ?ERROR("[time_tracker_card_api] Failed delete request with error: ~p", [Err]),
            {error, db_error}
    end.

-spec list_by_user(Args :: map()) ->
    {ok, Response :: map()} |
    {error, db_error}.
list_by_user(Args) ->
    UserId = maps:get(<<"user_id">>, Args),
    case time_tracker_db:query(?GET_USER_CARDS_QUERY, [UserId]) of
        {ok, _, CardsRaw} ->
            Cards = [CardId || {CardId} <- CardsRaw],
            {ok, #{<<"card_uids">> => Cards, <<"user_id">> => UserId}};
        Err ->
            ?ERROR("[time_tracker_card_api] Failed list_by_user request with error: ~p", [Err]),
            {error, db_error}
    end.

-spec delete_all_by_user(Args :: map()) ->
    {ok, Response :: map()} |
    {error, db_error}.
delete_all_by_user(Args) ->
    UserId = maps:get(<<"user_id">>, Args),
    case time_tracker_db:query(?DELETE_CARDS_BY_USER_QUERY, [UserId]) of
        {ok, _, _, CardsRaw} ->
            Cards = [CardId || {CardId} <- CardsRaw],
            {ok, #{<<"card_uids">> => Cards, <<"user_id">> => UserId}};
        Err ->
            ?ERROR("[time_tracker_card_api] Failed delete_all_by_user request with error: ~p", [Err]),
            {error, db_error}
    end.
