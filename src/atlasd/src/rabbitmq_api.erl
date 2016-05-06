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
-include_lib("rabbitmq_monitor.hrl").

%% API
-export([
  get_all_queues/1,
  request/3,
  auth_header/2,
  get_queue_by_name/2,
  get_queues_by_vhost/1,
  get_data/3,
  format_queue/1]).


get_queue_by_name(Monitor, Queue) ->
  Data = get_data("/queues/" ++ Monitor#rabbitmq_monitor.vhost ++ "/" ++ Queue, get, Monitor),
  if
    Data == [] -> maps:new();
    true -> %?DBG("Request success"),
      Queue = format_queue(Data),
      #{Queue#rabbitmq_queue.name => Queue}
  end.

get_queues_by_vhost(Monitor) ->
  Data = get_data("/queues/" ++ Monitor#rabbitmq_monitor.vhost, get, Monitor),
  make_queues_map(Data).

get_all_queues(Monitor) ->
  Data = get_data("/queues", get, Monitor),
  make_queues_map(Data).


make_queues_map(Data) -> make_queues_map(Data, maps:new()).

make_queues_map([], Result) -> Result;
make_queues_map([Q | T], Result) ->
  Queue = format_queue(Q),
  make_queues_map(T, maps:put(Queue#rabbitmq_queue.name, Queue, Result)).


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
  #rabbitmq_queue{
    name = binary_to_list(Name),
    messages = Messages,
    consumers = Consumers,
    publish_rate = Publish_rate,
    ack_rate = Ack_rate
  }.

get_data(Url, Method, Monitor) ->
  case request(Url, Method, Monitor) of
    {ok, 200, Data} ->
      jiffy:decode(Data, [return_maps]);
    Rslt ->
      ?DBG("Request failed: ~p, ~p", [Rslt, Monitor]),
      []
  end.

auth_header(User, Pass) ->
  Encoded = base64:encode_to_string(lists:append([User, ":", Pass])),
  {"Authorization", "Basic " ++ Encoded}.

request(Url, Method, Monitor) ->
  URL = "http://" ++ Monitor#rabbitmq_monitor.host ++ ":" ++ Monitor#rabbitmq_monitor.port ++ "/api" ++ Url,
  Headers = [auth_header(Monitor#rabbitmq_monitor.user, Monitor#rabbitmq_monitor.pass), {"Content-Type", "application/json"}],
  {Result, { Status, _, Body}} = httpc:request(Method, {URL, Headers}, [], []),
  {_, Status_code, _} = Status,
  {Result, Status_code, Body}.
