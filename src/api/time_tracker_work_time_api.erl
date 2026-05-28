-module(time_tracker_work_time_api).

%% API
-export([set/1]).
-export([get/1]).
-export([add_exclusion/1]).
-export([delete_exclusion/1]).
-export([get_exclusion/1]).
-export([history_by_user/1]).
-export([statistic_by_user/1]).

-include("time_tracker.hrl").

%% SQL
-define(SET_WORK_TIME_QUERY, "
    UPDATE users
    SET 
        expected_start_time = $2,
        expected_stop_time = $3,
        expected_days = $4 
    WHERE id = $1
").

-define(GET_WORK_TIME_QUERY, "
    SELECT expected_start_time, expected_stop_time, expected_days
    FROM users
    WHERE id = $1
").

-define(GET_FIRST_DATE_QUERY, "
    SELECT
        reg_date, 
	    (SELECT extract(epoch from(expected_stop_time - expected_start_time)) / 60)::integer as total_mins,
	    expected_days
    FROM users
    WHERE id = $1
").

-define(ADD_EXCLUSION_QUERY, "
    INSERT INTO user_exclusions (user_id, start_datetime, stop_datetime, type_exclusion)
    VALUES ($1, $2, $3, $4)
    RETURNING id
").

-define(DELETE_EXCLUSION_QUERY, "
    DELETE FROM user_exclusions
    WHERE id = $1
").

-define(GET_EXCLUSION_QUERY, "
    SELECT id, start_datetime, stop_datetime, type_exclusion
    FROM user_exclusions
    WHERE user_id = $1
").

-define(GET_HISTORY_QUERY, "
    SELECT date, start_time, stop_time
    FROM time_log
    WHERE user_id = $1
").

-define(GET_STATISTIC_QUERY, "
    SELECT
        sum(total_mins) as worked_mins,
	    count(is_late) FILTER (WHERE is_late) AS late_count,
        count(is_late) FILTER (WHERE is_late AND is_late_reason) as late_reason_count,
	    count(is_leave) FILTER (WHERE is_leave) as leave_count,
        count(is_leave) FILTER (WHERE is_leave AND is_leave_reason) as leave_reason_count,
        (
            SELECT COALESCE(SUM(
                (LEAST(stop_datetime::date, $3::date) - GREATEST(start_datetime::date, $2::date)) + 1
            ), 0) AS days_off
            FROM user_exclusions
            WHERE user_id = $1 AND type_exclusion = 'full-time' AND start_datetime <= $3 AND stop_datetime  >= $2
        ) as leave_days
    FROM time_log 
    WHERE user_id = $1 AND (date BETWEEN $2 AND $3)
").

%% API
-spec set(Args :: map()) ->
    {ok, Response :: map()} |
    {error, db_error}.
set(Args) ->
    UserId    = maps:get(<<"user_id">>, Args),
    StartTime = maps:get(<<"start_time">>, Args),
    StopTime  = maps:get(<<"end_time">>, Args),
    Days      = maps:get(<<"days">>, Args),
    case time_tracker_db:query(?SET_WORK_TIME_QUERY, [UserId, StartTime, StopTime, Days]) of
        {ok, 1} ->
            ok;
        Err ->
            ?ERROR("[time_tracker_work_time_api] Failed set request with error: ~p", [Err]),
            {error, db_error}
    end.

-spec get(Args :: map()) ->
    {ok, Response :: map()} |
    {error, db_error}.
get(Args) ->
    UserId = maps:get(<<"user_id">>, Args),
    case time_tracker_db:query(?GET_WORK_TIME_QUERY, [UserId]) of
        {ok, _, [{StartTime, StopTime, Days}]} ->
            Map = #{
                <<"user_id">>    => UserId,
                <<"start_time">> => time_tracker_utils:time_to_binary(StartTime),
                <<"end_time">>   => time_tracker_utils:time_to_binary(StopTime),
                <<"days">>       => Days
            },
            {ok, Map};
        Err ->
            ?ERROR("[time_tracker_work_time_api] Failed get request with error: ~p", [Err]),
            {error, db_error}
    end.

-spec add_exclusion(Args :: map()) ->
    {ok, Response :: map()} |
    {error, db_error}.
add_exclusion(Args) ->
    UserId        = maps:get(<<"user_id">>, Args),
    StartDateTime = maps:get(<<"start_datetime">>, Args),
    StopDateTime  = maps:get(<<"end_datetime">>, Args),
    TypeExclusion = maps:get(<<"type_exclusion">>, Args),
    case time_tracker_db:query(?ADD_EXCLUSION_QUERY, [UserId, StartDateTime, StopDateTime, TypeExclusion]) of
        {ok, 1, _, [{ExclusionId}]} ->
            Exclusion = #{
                <<"id">>             => ExclusionId,
                <<"start_datetime">> => StartDateTime,
                <<"end_datetime">>   => StopDateTime,
                <<"type_exclusion">> => TypeExclusion
            },
            {ok, #{<<"exclusion">> => Exclusion, <<"user_id">> => UserId}};
        Err ->
            ?ERROR("[time_tracker_work_time_api] Failed add exlusion request with error: ~p", [Err]),
            {error, db_error}
    end.

-spec delete_exclusion(Args :: map()) ->
    {ok, Response :: map()} |
    {error, db_error}.
delete_exclusion(Args) ->
    ExclusionId = maps:get(<<"id">>, Args),
    case time_tracker_db:query(?DELETE_EXCLUSION_QUERY, [ExclusionId]) of
        {ok, 1} ->
            ok;
        Err ->
            ?ERROR("[time_tracker_work_time_api] Failed delete exlusion request with error: ~p", [Err]),
            {error, db_error}
    end.

-spec get_exclusion(Args :: map()) ->
    {ok, Response :: map()} |
    {error, db_error}.
get_exclusion(Args) ->
    UserId = maps:get(<<"user_id">>, Args),
    case time_tracker_db:query(?GET_EXCLUSION_QUERY, [UserId]) of
        {ok, _, ExclusionsRaw} ->
            Exclusions = [
                #{
                    <<"id">>             => ExclusionId,
                    <<"start_datetime">> => StartDateTime,
                    <<"end_datetime">>   => StopDateTime,
                    <<"type_exclusion">> => TypeExclusion
                }
            || {ExclusionId, StartDateTime, StopDateTime, TypeExclusion} <- ExclusionsRaw],
            {ok, #{<<"exclusions">> => Exclusions, <<"user_id">> => UserId}};
        Err ->
            ?ERROR("[time_tracker_work_time_api] Failed get exlusions request with error: ~p", [Err]),
            {error, db_error}
    end.

-spec history_by_user(Args :: map()) ->
    {ok, Response :: map()} |
    {error, db_error}.
history_by_user(Args) ->
    UserId = maps:get(<<"user_id">>, Args),
    case time_tracker_db:query(?GET_HISTORY_QUERY, [UserId]) of
        {ok, _, HistoryRaw} ->
            History = [
                #{
                    <<"date">>       => Date,
                    <<"start_time">> => time_tracker_utils:time_to_binary(StartTime),
                    <<"end_time">>   => time_tracker_utils:time_to_binary(StopTime)
                }
            || {Date, StartTime, StopTime} <- HistoryRaw],
         {ok, #{<<"history">> => History, <<"user_id">> => UserId}};
        Err ->
            ?ERROR("[time_tracker_work_time_api] Failed get history request with error: ~p", [Err]),
            {error, db_error}
    end.

-spec statistic_by_user(Args :: map()) ->
    {ok, Response :: map()} |
    {error, db_error}.
statistic_by_user(Args) ->
    UserId = maps:get(<<"user_id">>, Args),
    Filter = maps:get(<<"filter">>, Args),
    {ok, _, [{UserFirstDate, DayMins, DaysAtWeek}]} = time_tracker_db:query(?GET_FIRST_DATE_QUERY, [UserId]),
    {FirstDate, LastDate} = get_filter_period(Filter, UserFirstDate),
    ?INFO("[time_tracker_work_time_api] Period: ~p, Dates: ~p - ~p", [Filter, FirstDate, LastDate]),
    case time_tracker_db:query(?GET_STATISTIC_QUERY, [UserId, FirstDate, LastDate]) of
        {ok, _, [{WorkedMins, Late, LateReason, Leave, LeaveReason, Vacation}]} ->
            Days = get_days_diff(FirstDate, LastDate),
            Weekends = ((Days div 7) * (7 - DaysAtWeek)), %% Грубий розрахунок вихідних днів, без урахування поточного для тижня
            TotalDays = Days - Weekends - Vacation,
            TotalMins = (TotalDays * DayMins),
            UnderMins = case TotalMins - WorkedMins of
                Diff when Diff > 0 ->
                    Diff;
                _ ->
                    0
            end,
            Stat = #{
                <<"days">> => #{
                    <<"work_days">> => TotalDays,
                    <<"weekends">>  => Weekends,
                    <<"leave">>     => Vacation
                },
                <<"time">> => #{
                    <<"worked">>    => time_tracker_utils:time_to_binary({WorkedMins div 60, WorkedMins rem 60, 0}),
                    <<"total">>     => time_tracker_utils:time_to_binary({TotalMins div 60, TotalMins rem 60, 0}),
                    <<"undertime">> => time_tracker_utils:time_to_binary({UnderMins div 60, UnderMins rem 60, 0})
                },
                <<"late_count">>  => #{
                    <<"without_reason">> => Late - LateReason,
                    <<"with_reason">>    => LateReason
                },
                <<"leave_count">> => #{
                    <<"without_reason">> => Leave - LeaveReason,
                    <<"with_reason">>    => LeaveReason
                }
            },
            {ok, #{<<"statistic">> => Stat, <<"user_id">> => UserId}};
        Err ->
            ?ERROR("[time_tracker_work_time_api] Failed get statistic request with error: ~p", [Err]),
            {error, db_error}
    end.

%% internal
get_filter_period(<<"week">>, UserFirstDate) ->
    CurrentDate = date(),
    DayOfWeek = calendar:day_of_the_week(CurrentDate),
    FirstDays = calendar:date_to_gregorian_days(CurrentDate) - (DayOfWeek - 1),
    FirstDate = calendar:gregorian_days_to_date(FirstDays),
    LastDays = FirstDays + 6,
    LastDate = calendar:gregorian_days_to_date(LastDays),
    {erlang:max(FirstDate, UserFirstDate), LastDate};
get_filter_period(<<"month">>, UserFirstDate) ->
    {Year, Month, _} = date(),
    FirstDate = {Year, Month, 1},
    LastDate = {Year, Month, calendar:last_day_of_the_month(Year, Month)},
    {erlang:max(FirstDate, UserFirstDate), LastDate};
get_filter_period(<<"year">>, UserFirstDate) ->
    {Year, _, _} = date(),
    FirstDate = {Year, 1, 1},
    LastDate = {Year, 12, 31},
    {erlang:max(FirstDate, UserFirstDate), LastDate};
get_filter_period(<<"all_time">>, UserFirstDate) ->
    {UserFirstDate, date()}.

get_days_diff(DateFrom, DateTo) ->
    DaysFrom = calendar:date_to_gregorian_days(DateFrom),
    DaysTo = calendar:date_to_gregorian_days(DateTo),
    DaysTo - DaysFrom.
