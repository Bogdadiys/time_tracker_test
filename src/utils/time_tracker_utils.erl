-module(time_tracker_utils).

-export([time_to_binary/1]).

time_to_binary(null) ->
    <<"">>;
time_to_binary({Hours, Minutes, Seconds}) ->
    HoursBin = format_time(integer_to_binary(Hours)),
    MinutesBin = format_time(integer_to_binary(Minutes)),
    SecondsBin = format_time(integer_to_binary(round(Seconds))),
    <<HoursBin/binary, ":", MinutesBin/binary, ":", SecondsBin/binary>>.


format_time(<<TT:1/binary>>) ->
    <<"0", TT/binary>>;
format_time(TT) ->
    TT.