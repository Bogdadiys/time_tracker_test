-module(time_tracker_http_handler).
-behaviour(cowboy_handler).

%% cowboy_handler callbacks
-export([init/2]).

-include("time_tracker.hrl").
-define(RESPONSE_HEADERS, #{<<"content-type">> => <<"application/json">>}).

%% cowboy_handler callbacks
init(Req, State) ->
    Method      = cowboy_req:method(Req),
    Path        = cowboy_req:path(Req),
    Headers     = cowboy_req:headers(Req),
    ContentType = cowboy_req:header(<<"content-type">>, Req, <<"application/json">>),
    {ok, Body, Req1} = read_body(Req),
    NewReq = try
        {Code, RespHeaders, Resp} = case time_tracker_protocol:decode(ContentType, Body) of
            {ok, Args} ->
                handle_request(Method, Path, Args);
            _ ->
                {415, #{}, <<>>}
        end,
        cowboy_req:reply(Code, RespHeaders, Resp, Req1)
    catch
        Type:Reason:Stacktrace ->
            ErrLog = "[time_tracker_http_handler] Method: ~p, Path: ~p, Headers: ~p, Body: ~p, "
                "Exception Type: ~p, Reason: ~p, Stacktrace: ~p",
            ?ERROR(ErrLog, [Method, Path, Headers, Body, Type, Reason, Stacktrace]),
            cowboy_req:reply(500, #{}, <<>>, Req1)
    end,
    {ok, NewReq, State}.

%% internal
handle_request(<<"POST">> = Method, Path, Args) ->
    case time_tracker_validator:validate(Path, Args) of
        {ok, Data} ->
            dispatch(Path, Data);
        Err ->
            DebugLog = "[time_tracker_http_handler] Method: ~p, Path: ~p, Validation failed: ~p",
            ?DEBUG(DebugLog, [Method, Path, Err]),
            {ok, Response} = time_tracker_handler_utils:encode_result({error, <<"validation failed">>}),
            {422, ?RESPONSE_HEADERS, Response}
    end;
handle_request(Method, Path, _Args) ->
    DebugLog = "[time_tracker_http_handler] Invalid Method: ~p, Path: ~p",
    ?DEBUG(DebugLog, [Method, Path]),
    {405, #{}, <<>>}.

dispatch(Path, Args) ->
    Result = time_tracker_handler_utils:dispatch(Path, Args),
    {ok, Response} = time_tracker_handler_utils:encode_result(Result),
    Code = case Result of
        {error, not_found} ->
            404;
        {error, _} ->
            500;
        _ ->
            200
    end,
    {Code, ?RESPONSE_HEADERS, Response}.

read_body(Req) ->
    Res = cowboy_req:read_body(Req),
    read_body(Res, <<>>).

read_body({ok, Body, Req}, Acc) ->
    {ok, <<Acc/binary, Body/binary>>, Req};
read_body({more, Body, Req}, Acc) ->
    Res = cowboy_req:read_body(Req),
    read_body(Res, <<Acc/binary, Body/binary>>).
