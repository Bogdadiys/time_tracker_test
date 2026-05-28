-module(time_tracker_handler_utils).

-export([dispatch/2]).
-export([encode_result/1]).

dispatch(Path, Args) ->
    case Path of
        <<"/card/touch">> ->
            time_tracker_card_api:touch(Args);
        <<"/card/assign">> ->
            time_tracker_card_api:assign(Args);
        <<"/card/delete">> ->
            time_tracker_card_api:delete(Args);
        <<"/card/list_by_user">> ->
            time_tracker_card_api:list_by_user(Args);
        <<"/card/delete_all_by_user">> ->
            time_tracker_card_api:delete_all_by_user(Args);
        <<"/work_time/set">> ->
            time_tracker_work_time_api:set(Args);
        <<"/work_time/get">> ->
            time_tracker_work_time_api:get(Args);
        <<"/work_time/add_exclusion">> ->
            time_tracker_work_time_api:add_exclusion(Args);
        <<"/work_time/delete_exclusion">> ->
            time_tracker_work_time_api:delete_exclusion(Args);
        <<"/work_time/get_exclusion">> ->
            time_tracker_work_time_api:get_exclusion(Args);
        <<"/work_time/history_by_user">> ->
            time_tracker_work_time_api:history_by_user(Args);
        <<"/work_time/statistics_by_user">> ->
            time_tracker_work_time_api:statistic_by_user(Args);
        <<"/user/create">> ->
            time_tracker_user_api:create(Args);
        <<"/user/delete">> ->
            time_tracker_user_api:delete(Args);
        <<"/user/list">> ->
            time_tracker_user_api:list(Args);
        _ ->
            {error, not_found}
    end.

encode_result({ok, Data}) ->
    Body = #{
        <<"status">> => <<"ok">>,
        <<"response">> => Data
    },
    time_tracker_protocol:encode(Body);
encode_result(ok) ->
    Body = #{
        <<"status">> => <<"ok">>
    },
    time_tracker_protocol:encode(Body);
encode_result({error, Reason}) ->
    Body = #{
        <<"status">> => <<"error">>,
        <<"message">> => Reason
    },
    time_tracker_protocol:encode(Body).
