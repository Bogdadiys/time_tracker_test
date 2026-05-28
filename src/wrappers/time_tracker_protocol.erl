-module(time_tracker_protocol).

-export([decode/2]).
-export([encode/1]).

-spec decode(ContentType :: binary(), BinaryData :: binary()) ->
    {ok, map()} |
    {error, undefined_content_type}.
decode(<<"application/json", _/binary>>, BinaryData) ->
    {ok, jsx:decode(BinaryData, [return_maps])};
decode(_Type, _BinaryData) ->
    {error, undefined_content_type}.

-spec encode(Body :: map() | proplists:proplist()) ->
    {ok, binary()}.
encode(Body) ->
    encode(<<"application/json">>, Body).

encode(<<"application/json">>, Body) ->
    {ok, jsx:encode(Body)}.
