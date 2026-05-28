-module(time_tracker_mq_handler).
-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([terminate/2]).
-export([code_change/3]).

-include_lib("amqp_client/include/amqp_client.hrl").
-include("time_tracker.hrl").

-define(EXCHANGE, application:get_env(time_tracker_test, mq_exchange, <<"time_tracker_exchange">>)).
-define(QUEUE, <<"time_tracker_queue">>).
-define(ROUTING_KEY, <<"time_tracker_rk">>).

%% API
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% gen_server callbacks
init(_) ->
    ConsumerTag = generate_ct(),
    {ok, Connection} = time_tracker_amqp:start(),
    {ok, Channel} = time_tracker_amqp:open_channel(Connection),
    ok = time_tracker_amqp:declare_queue(Channel, ?QUEUE),
    ok = time_tracker_amqp:declare_exchange(Channel, ?EXCHANGE, <<"topic">>),
    ok = time_tracker_amqp:bind_queue(Channel, ?EXCHANGE, ?ROUTING_KEY),
    ok = time_tracker_amqp:basic_consume(Channel, ConsumerTag),
    State = #{
        connection => Connection,
        channel => Channel,
        connection_mref => erlang:monitor(process, Connection),
        channel_mref => erlang:monitor(process, Channel),
        consumer_tag => ConsumerTag
    },
    {ok, State}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({#'basic.deliver'{}, #amqp_msg{}} = Amqp, #{channel := Channel} = State) ->
    ?INFO("[time_tracker_mq_handler] New AMQP message: ~p", [Amqp]),
    {
        #'basic.deliver'{
            delivery_tag = DTag
        },
        #amqp_msg{
            props = #'P_basic'{
                reply_to = ReplyTo,
                correlation_id = CorrelationId,
                headers = Headers
            },
            payload = MsgBinary
        }
    } = Amqp,
    PrettyHeaders = [{Key, Value} || {Key, _Type, Value} <- Headers],
    Path        = proplists:get_value(<<"method">>, PrettyHeaders),
    ContentType = proplists:get_value(<<"content-type">>, PrettyHeaders, <<"application/json">>),
    Result = try
        {ok, Args} = time_tracker_protocol:decode(ContentType, MsgBinary),
        case time_tracker_validator:validate(Path, Args) of
            {ok, Data} ->
                time_tracker_handler_utils:dispatch(Path, Data);
            Err ->
                DebugLog = "[time_tracker_mq_handler] Path: ~p, Validation failed: ~p",
                ?DEBUG(DebugLog, [Path, Err]),
                {error, <<"validation failed">>}
        end
    catch
        Type:Reason:Stacktrace ->
            ErrLog = "[time_tracker_mq_handler] Path: ~p, Headers: ~p, Body: ~p, ReplyTo: ~p "
                "Exception Type: ~p, Reason: ~p, Stacktrace: ~p",
            ?ERROR(ErrLog, [Path, PrettyHeaders, MsgBinary, ReplyTo, Type, Reason, Stacktrace]),
            {error, <<"invalid_message">>}
    end,
    {ok, Response} = time_tracker_handler_utils:encode_result(Result),
    time_tracker_amqp:publish(Channel, <<"">>, Response, ReplyTo, CorrelationId),
    time_tracker_amqp:ack(Channel, DTag),
    {noreply, State};
handle_info(#'basic.consume_ok'{}, State) ->
    {noreply, State};
handle_info({'DOWN', MRef, _, Pid, Reason}, #{connection_mref := MRef} = State) ->
    ?WARNING("[time_tracker_mq_handler] AMQP connection ~p down with reason: ~p", [Pid, Reason]),
    {stop, {died_connection, Reason}, State};
handle_info({'DOWN', MRef, _, Pid, Reason}, #{channel_mref := MRef} = State) ->
    ?WARNING("[time_tracker_mq_handler] AMQP channel ~p down with reason: ~p", [Pid, Reason]),
    {stop, {died_channel, Reason}, State};
handle_info({'DOWN', _MRef, _, Pid, Reason}, #{channel := Pid} = State) ->
    ?WARNING("[time_tracker_mq_handler] AMQP channel ~p down with reason: ~p", [Pid, Reason]),
    {stop, {died_channel, Reason}, State};
handle_info(Info, State) ->
    ?INFO("[time_tracker_mq_handler] Got unexpected message: ~p", [Info]),
    {noreply, State}.

terminate(_Reason, #{connection := Connection, channel := Channel}) ->
    try
        _ = time_tracker_amqp:close_channel(Channel),
        _ = time_tracker_amqp:close(Connection)
    catch C:E:S ->
        Log = "[time_tracker_mq_handler] AMQP failed to close "
            "connection ~p and channel ~p with error: ~p, reason: ~p",
        ?WARNING(Log, [Connection, Channel, {C,E}, S])
    end,
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% internal
generate_ct() ->
    NodeBin      = atom_to_binary(node(), utf8),
    ModuleBin    = atom_to_binary(?MODULE, utf8),
    ProcessIdBin = unicode:characters_to_binary(erlang:pid_to_list(self())),
    <<NodeBin/binary, "-", ModuleBin/binary, "-", ProcessIdBin/binary>>.
