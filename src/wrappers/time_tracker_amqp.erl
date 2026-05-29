-module(time_tracker_amqp).

-export([start/0]).
-export([close/1]).
-export([open_channel/1]).
-export([close_channel/1]).
-export([declare_queue/2]).
-export([declare_exchange/3]).
-export([bind_queue/3]).
-export([basic_consume/2]).
-export([publish/5]).
-export([ack/2]).

-include_lib("amqp_client/include/amqp_client.hrl").

-spec start() ->
    {ok, pid()}
start() ->
    AmqpParams = get_amqp_params(),
    {ok, Connection} = amqp_connection:start(AmqpParams),
    {ok, Connection}.

-spec close(Connection :: pid()) ->
    ok |
    closing.
close(Connection) ->
    amqp_connection:close(Connection).

-spec open_channel(Connection :: pid()) ->
    {ok, pid()}.
open_channel(Connection) ->
    {ok, Channel} = amqp_connection:open_channel(Connection),
    {ok, Channel}.

-spec close_channel(Channel :: pid()) ->
    ok |
    closing
close_channel(Channel) ->
    amqp_channel:close(Channel).

-spec declare_queue(Channel :: pid(), Queue :: binary()) ->
    ok.
declare_queue(Channel, Queue) ->
    QueueDeclare = #'queue.declare'{queue = Queue, durable = true},
    #'queue.declare_ok'{} = amqp_channel:call(Channel, QueueDeclare),
    ok.

-spec declare_exchange(Channel :: pid(), Exchange :: binary(), Type :: binary()) ->
    ok.
declare_exchange(Channel, Exchange, Type) ->
    ExchangeDeclare = #'exchange.declare'{exchange = Exchange, type = Type},
    #'exchange.declare_ok'{} = amqp_channel:call(Channel, ExchangeDeclare), 
    ok.

-spec bind_queue(Channel :: pid(), Exchange :: binary(), RoutingKey :: binary()) ->
    ok.
bind_queue(Channel, Exchange, RoutingKey) ->
    QueueBind = #'queue.bind'{exchange = Exchange, routing_key = RoutingKey},
    #'queue.bind_ok'{} = amqp_channel:call(Channel, QueueBind),
    ok.

-spec basic_consume(Channel :: pid(), ConsumerTag :: binary()) ->
    ok.
basic_consume(Channel, ConsumerTag) ->
    BasicConsume = #'basic.consume'{no_ack = false, consumer_tag = ConsumerTag},
    #'basic.consume_ok'{} = amqp_channel:call(Channel, BasicConsume),
    ok.

-spec publish(Channel :: pid(), Exchange :: binary(), Payload :: binary(), RoutingKey :: binary(), CorrelationId :: binary()) ->
    ok.
publish(Channel, Exchange, Payload, RoutingKey, CorrelationId) ->
    Publish = #'basic.publish'{routing_key = RoutingKey, exchange = Exchange},
    RespMsg = #amqp_msg{
        props = #'P_basic'{correlation_id = CorrelationId},
        payload = Payload
    },
    amqp_channel:cast(Channel, Publish, RespMsg).

-spec ack(Channel :: pid(), DeliveryTag :: integer()) ->
    ok.
ack(Channel, DTag) ->
    amqp_channel:cast(Channel, #'basic.ack'{delivery_tag = DTag}).

%% internal
get_amqp_params() ->
    User     = application:get_env(time_tracker_test, mq_username, <<"guest">>),
    Password = application:get_env(time_tracker_test, mq_password, <<"guest">>),
    Host     = application:get_env(time_tracker_test, mq_host, "localhost"),
    #amqp_params_network{
        username = User,
        password = Password,
        host     = Host
    }.
