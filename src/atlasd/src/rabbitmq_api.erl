%%%-------------------------------------------------------------------
%%% @author user
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 10. Дек. 2015 10:39
%%%-------------------------------------------------------------------
-module(rabbitmq_api).
-author("user").
-include_lib("atlasd.hrl").

%% API
-export([
  main/0,
  get_all_queues/1,
  request/3,
  auth_header/2,
  get_queue_by_name/1,
  get_queues_by_vhost/1,
  get_data/3,
  format_queue/1]).


-record(queue, {name,
  messages,
  consumers,
  publish_rate,
  ack_rate}).

-record(state, {
  mode = api :: api | native,
  host = "127.0.0.1",
  port = "15672",
  user = "guest",
  pass = "guest",
  vhost = "%2f",
  minutes_to_add_consumers,
  exchange,
  queue,
  task
}).

main() ->
  inets:start(),
  State = #state{
    host = "***REMOVED***",
    port = "15672",
    user = "guest",
    pass = "guest",
    vhost = "%2f",
    queue = "ds.conveyor.router.ac",
    minutes_to_add_consumers = 1000
  },
  %get_queue_by_name(State).
  ?DBG("~p ", get_all_queues(State)).

get_queue_by_name(State) ->
  Data = get_data("/queues/" ++ State#state.vhost ++ "/" ++ State#state.queue, get, State),
  if
    Data == [] -> false;
    true -> %?DBG("Request success"),
      format_queue(Data)
  end.

get_queues_by_vhost(State) ->
  Data = get_data("/queues/" ++ State#state.vhost, get, State),
  make_queues_list(Data).

get_all_queues(State) ->
  Data = get_data("/queues", get, State),
  make_queues_list(Data).

make_queues_list([Q|T]) ->
  [format_queue(Q) | make_queues_list(T)];

make_queues_list([]) ->
  [].

format_queue(Queue) ->
  Name = maps:get(<<"name">>, Queue),
  Messages = maps:get(<<"messages">>, Queue),
  Consumers = maps:get(<<"consumers">>, Queue),
  Publish_rate = try nested:get([<<"message_stats">>, <<"publish_details">>, <<"rate">>], Queue, []) of
                   PRate -> PRate
                 catch
                   _:_ -> 0.0
                 end,
  Ack_rate = try nested:get([<<"message_stats">>, <<"ack_details">>, <<"rate">>], Queue, []) of
               ARate -> ARate
             catch
               _:_ -> 0.0
             end,
  #queue{
    name = binary_to_list(Name),
    messages = Messages,
    consumers = Consumers,
    publish_rate = Publish_rate,
    ack_rate = Ack_rate
  }.

get_data(Url, Method, State) ->
  case request(Url, Method, State) of
    {ok, 200, Data} ->
      jiffy:decode(Data, [return_maps]);
    Rslt ->
      ?DBG("Request failed: ~p, ~p", [Rslt, State]),
      []
  end.

auth_header(User, Pass) ->
  Encoded = base64:encode_to_string(lists:append([User, ":", Pass])),
  {"Authorization", "Basic " ++ Encoded}.

request(Url, Method, State) ->
  URL = "http://" ++ State#state.host ++ ":" ++ State#state.port ++ "/api" ++ Url,
  %?DBG(URL),
  Headers = [auth_header(State#state.user, State#state.pass), {"Content-Type", "application/json"}],
  {Result, { Status, _, Body}} = httpc:request(Method, {URL, Headers}, [], []),
  {_, Status_code, _} = Status,
  {Result, Status_code, Body}.