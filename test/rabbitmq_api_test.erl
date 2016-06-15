%%%-------------------------------------------------------------------
%%% @author user
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 10. Дек. 2015 18:12
%%%-------------------------------------------------------------------
-module(rabbitmq_api_test).
-author("user").

-include_lib("eunit/include/eunit.hrl").

-record(state, {
  mode = api :: api | native,
  host = "dbx.pravo.ru",
  port = "15672",
  user = "guest",
  pass = "guest",
  vhost = "%2f",
  minutes_to_add_consumers = 1000,
  exchange,
  queue = "ds.conveyor.router.ac",
  task
}).

-record(queue, {name,
  messages,
  consumers,
  publish_rate,
  ack_rate}).

setup() ->
  inets:start().

rabbitmq_api_request_failed_test() ->
  inets:start(),
  State = #state{},
  ?assertMatch({ok, 404, _}, rabbitmq_api:request("/test", get, State)).

rabbitmq_api_request_success_test() ->
  State = #state{},
  ?assertMatch({ok, 200, _}, rabbitmq_api:request("/overview", get, State)).

rabbitmq_api_auth_header_test() ->
  ?assertEqual({"Authorization","Basic dGVzdDp0ZXN0"}, rabbitmq_api:auth_header("test", "test")).

rabbitmq_api_get_data_failed_test() ->
  State = #state{},
  ?assertEqual([], rabbitmq_api:get_data("/test", get, State)).

rabbitmq_api_get_data_success_test() ->
  State = #state{},
  Data = rabbitmq_api:get_data("/overview", get, State),
  [Contexts] = maps:get(<<"contexts">>, Data),
  ?assertEqual(State#state.port, integer_to_list(maps:get(<<"port">>, Contexts))).

rabbitmq_api_format_queue_test() ->
  State = #state{},
  Data = rabbitmq_api:get_data("/queues/" ++ State#state.vhost ++ "/" ++ State#state.queue, get, State),
  Queue = rabbitmq_api:format_queue(Data),
  ?assertEqual(State#state.queue, Queue#queue.name).

rabbitmq_api_proccess_queue_success_test() ->
  State = #state{},
  Queue = rabbitmq_api:get_queue_by_name(State),
  ?assertEqual(ok, monitor_rabbitmq:process_queue(Queue, State)).

rabbitmq_api_proccess_queue_failed_test() ->
  State = #state{queue = "test"},
  Queue = rabbitmq_api:get_queue_by_name(State),
  ?assertEqual(failed, monitor_rabbitmq:process_queue(Queue, State)).