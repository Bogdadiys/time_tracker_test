-module(time_tracker_db).

-export([connect/0]).
-export([close/1]).
-export([equery/3]).

-export([query/2]).
-export([to_map/2]).

-spec connect() ->
    {ok, Connection :: pid()} | {error, Reason :: atom() | tuple()}.
connect() ->
    Host     = application:get_env(time_tracker_test, db_host, "localhost"),
    Port     = application:get_env(time_tracker_test, db_port, 5432),
    User     = application:get_env(time_tracker_test, db_user, "user"),
    Password = application:get_env(time_tracker_test, db_password, "password"),
    Timeout  = application:get_env(time_tracker_test, db_timeout, 5000),
    Opts = #{
        host     => Host,
        port     => Port,
        username => User,
        password => Password,
        timeout  => Timeout
    },
    epgsql:connect(Opts).

- spec close(Connection :: pid()) -> ok.
close(Connection) ->
    epgsql:close(Connection).

-spec equery(Connect :: pid(), Query :: string(), Params :: list()) ->
    {ok, Columns :: list(), Rows :: list()} |
    {ok, Count :: integer()} |
    {ok, Count :: integer(), Column :: list(), Rows :: list()} |
    {error, Error :: atom() | tuple()}.
equery(Connect, Query, Params) ->
    epgsql:equery(Connect, Query, Params).

query(Query, Params) ->
    {ok, Connection} = connect(),
    Res = equery(Connection, Query, Params),
    close(Connection),
    Res.

to_map([{column,_,_,_,_,_,_,_,_}|_] = Columns0, Rows) ->
    Columns = [Column||{column,Column,_,_,_,_,_,_,_} <- Columns0],
    to_map(Columns, Rows);
to_map(Columns, Rows) ->
    [begin
        ValuesList = tuple_to_list(Row),
        Proplist = lists:zip(Columns, ValuesList),
        maps:from_list(Proplist)
    end || Row <- Rows].