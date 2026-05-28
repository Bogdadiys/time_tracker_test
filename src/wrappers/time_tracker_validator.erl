-module(time_tracker_validator).

%% API
-export([validate/2]).
-export([add_rules/0]).
%% Rules
-export([uuid/3]).
-export([time/3]).
-export([iso_dt/3]).

%% API
-spec validate(Path :: binary(), Data :: map()) ->
    {ok, map()} |
    {error, map()}.
validate(<<"/card/touch">>, Data) ->
    Schema = #{
        <<"card_uid">> => [required, uuid]
    },
    liver:validate(Schema, Data, #{return => map});
validate(<<"/card/assign">>, Data) ->
    Schema = #{
        <<"card_uid">> => [required, uuid],
        <<"user_id">>  => [required, positive_integer]
    },
    liver:validate(Schema, Data, #{return => map});
validate(<<"/card/delete">>, Data) ->
    Schema = #{
        <<"card_uid">> => [required, uuid]
    },
    liver:validate(Schema, Data, #{return => map});
validate(<<"/card/list_by_user">>, Data) ->
    Schema = #{
        <<"user_id">> => [required, positive_integer]
    },
    liver:validate(Schema, Data, #{return => map});
validate(<<"/card/delete_all_by_user">>, Data) ->
    Schema = #{
        <<"user_id">> => [required, positive_integer]
    },
    liver:validate(Schema, Data, #{return => map});
validate(<<"/work_time/set">>, Data) ->
    Schema = #{
        <<"user_id">> => [required, positive_integer],
        <<"start_time">> => [required, time],
        <<"end_time">> => [required, time],
        <<"days">> => [required, positive_integer]
    },
    liver:validate(Schema, Data, #{return => map});
validate(<<"/work_time/get">>, Data) ->
    Schema = #{
        <<"user_id">> => [required, positive_integer]
    },
    liver:validate(Schema, Data, #{return => map});
validate(<<"/work_time/add_exclusion">>, Data) ->
    Schema = #{
        <<"user_id">> => [required, positive_integer],
        <<"type_exclusion">> => [required, string, {one_of, [<<"come later">>, <<"leave earlier">>, <<"full-time">>]}],
        <<"start_datetime">> => [required, iso_dt],
        <<"end_datetime">> => [required, iso_dt]
    },
    liver:validate(Schema, Data, #{return => map});
validate(<<"/work_time/delete_exclusion">>, Data) ->
    Schema = #{
        <<"id">> => [required, positive_integer]
    },
    liver:validate(Schema, Data, #{return => map});
validate(<<"/work_time/get_exclusion">>, Data) ->
    Schema = #{
        <<"user_id">> => [required, positive_integer]
    },
    liver:validate(Schema, Data, #{return => map});
validate(<<"/work_time/history_by_user">>, Data) ->
    Schema = #{
        <<"user_id">> => [required, positive_integer]
    },
    liver:validate(Schema, Data, #{return => map});
validate(<<"/work_time/statistics_by_user">>, Data) ->
    Schema = #{
        <<"user_id">> => [required, positive_integer],
        <<"filter">> => [string, {one_of, [<<"week">>, <<"month">>, <<"year">>, <<"all_time">>]}, {default, <<"month">>}]
    },
    liver:validate(Schema, Data, #{return => map});
validate(<<"/user/create">>, Data) ->
    Schema = #{
        <<"user_name">> => [required, string]
    },
    liver:validate(Schema, Data, #{return => map});
validate(<<"/user/delete">>, Data) ->
    Schema = #{
        <<"user_id">> => [required, positive_integer]
    },
    liver:validate(Schema, Data, #{return => map});
validate(<<"/user/list">>, Data) ->
    Schema = #{
    },
    liver:validate(Schema, Data, #{return => map});
validate(_Path, Data) ->
    {ok, Data}.

-spec add_rules() -> ok.
add_rules() ->
    ok = liver:add_rule(uuid, ?MODULE),
    ok = liver:add_rule(time, ?MODULE),
    ok = liver:add_rule(iso_dt, ?MODULE).

%% RULES
-spec uuid(Args :: any(), Value :: any(), Opts :: any()) ->
    {ok, string()} |
    {error, format_error}.
uuid(_Args, <<_:36/binary>> = Value, _Opts)->
    Pattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
    case re:run(Value, Pattern, [{capture, none}]) of
        match ->
            {ok, Value};
        nomatch ->
            {error, format_error}
    end;
uuid(_Args, _Value, _Opts) ->
    {error, format_error}.

-spec time(Args :: any(), Value :: any(), Opts :: any()) ->
    {ok, calendar:time()} |
    {error, format_error}.
time(_Args, <<Hours:2/binary, ":", Minutes:2/binary, ":", Seconds:2/binary, _Other/binary>>, _Opts) ->
    time_validate(Hours, Minutes, Seconds);
time(_Args, _Value, _Opts) ->
    {error, format_error}.

-spec iso_dt(Args :: any(), Value :: any(), Opts :: any()) ->
    {ok, calendar:datetime()} |
    {error, format_error}.
iso_dt(_Args, <<Year:4/binary, "-", Month:2/binary, "-", Day:2/binary, "T",
                Hours:2/binary, ":", Minutes:2/binary, ":", Seconds:2/binary, _Other/binary>>, _Opts) ->
    iso_dt_validate(Year, Month, Day, Hours, Minutes, Seconds);
iso_dt(_Args, _Value, _Opts) ->
    {error, format_error}.

%% internal
time_validate(HoursBin, MinutesBin, SecondsBin) ->
    Time = try
        format_time(HoursBin, MinutesBin, SecondsBin)
    catch
        _:_:_ ->
            {{0, 0, 0}, {0, 0, 0}}
    end,
    case valid_time(Time) of
        true ->
            {ok, Time};
        _ ->
            {error, format_error}
    end.

iso_dt_validate(YearBin, MonthBin, DayBin, HoursBin, MinutesBin, SecondsBin) ->
    Datetime = try
        {format_date(YearBin, MonthBin, DayBin), format_time(HoursBin, MinutesBin, SecondsBin)}
    catch
        _:_:_ ->
            {{0, 0, 0}, {0, 0, 0}}
    end,
    {Date, Time} = Datetime,
    case calendar:valid_date(Date) and valid_time(Time) of
        true ->
            {ok, Datetime};
        _ ->
            {error, format_error}
    end.

format_date(YearBin, MonthBin, DayBin) ->
    Year  = binary_to_integer(YearBin),
    Month = binary_to_integer(MonthBin),
    Day   = binary_to_integer(DayBin),
    {Year, Month, Day}.

format_time(HoursBin, MinutesBin, SecondsBin) ->
    Hours   = binary_to_integer(HoursBin),
    Minutes = binary_to_integer(MinutesBin),
    Seconds = binary_to_integer(SecondsBin),
    {Hours, Minutes, Seconds}.

valid_time({H, M, S}) when
    H >= 0 andalso H < 24 andalso
    M >= 0 andalso M < 60 andalso
    S >= 0 andalso S < 60 ->
    true;
valid_time(_Time) ->
    false.
