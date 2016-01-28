-module(api_callback).
-export([handle/2, handle_event/3]).

-include_lib("elli/include/elli.hrl").
-behaviour(elli_handler).
-include_lib("atlasd.hrl").
-include_lib("kernel/include/file.hrl").

-export([render/2]).

%%
%% ELLI REQUEST CALLBACK
%%

handle(Req, _Args) ->
  %% Delegate to our handler function
  handle(Req#req.method, elli_request:path(Req), Req).

%% Route METHOD & PATH to the appropriate clause
handle('GET',[<<"nodes">>], _Req) ->
  {Response_status, Nodes} = atlasd:get_nodes(),

  Nodes_sorted_list = lists:sort(
    fun(Node1, Node2) -> maps:get(master_node, element(2, Node1)) =:= true end,
    maps:to_list(Nodes)
  ),

  Nodes_list_html = render(Nodes_sorted_list, ""),
  Data = dict:from_list([
    {title, "Nodes"},
    {content, Nodes_list_html}
  ]),
  {ok, Layout} = file:read_file('/apps/atlasd/assets/layout.html'),
  Html = mustache:render(binary_to_list(Layout), Data),

  {ok, [], Html};

handle(_, _, _Req) ->
  {404, [], <<"Not Found">>}.


render([], Result) -> Result;
render([Node | Nodes], Result) ->
  {ok, Widget} = file:read_file('/apps/atlasd/assets/widgets/node.item.html'),

  Node_data = element(2,Node),

  Name = maps:get(name, Node_data),

  Is_master_node = maps:get(master_node, Node_data),
  Master_tag = case Is_master_node of
                 true -> "<span class=\"label label-primary\">Master</span>";
                 false -> ""
               end,

  Is_master = maps:get(is_master, Node_data),
  Is_worker = maps:get(is_worker, Node_data),
  Master = case Is_master of true -> "<span class=\"badge\">Master</span>"; false -> "" end,
  Worker = case Is_worker of true -> "<span class=\"badge\">Worker</span>"; false -> "" end,
  Ability = Master ++ Worker,

  Stats = maps:get(stats, Node_data),

  Per_cpu = maps:get(per_cpu, maps:get(cpu, Stats)),
  Per_cpu_html = case Per_cpu of
    [] -> "";
    _ -> string:join(lists:map(fun(Int) -> io_lib:format("~.6f", [Int]) end, maps:get(per_cpu, maps:get(cpu, Stats))), "<br>")
  end,

  Data = dict:from_list([
    {name, Name},
    {master_tag, Master_tag},
    {ability, Ability},
    {free_memory, maps:get(free_memory, maps:get(mem, Stats))},
    {allocated_memory, maps:get(allocated_memory, maps:get(mem, Stats))},
    {overloaded, maps:get(overloaded, Stats)},
    {load_average, maps:get(load_average, maps:get(cpu, Stats))},
    {per_cpu, Per_cpu_html}
  ]),

  Html = mustache:render(binary_to_list(Widget), Data),
  render(Nodes, Result ++ Html).

%%
%% ELLI EVENT CALLBACKS
%%


%% elli_startup is sent when Elli is starting up. If you are
%% implementing a middleware, you can use it to spawn processes,
%% create ETS tables or start supervised processes in a supervisor
%% tree.
handle_event(elli_startup, [], _) -> ok;

%% request_complete fires *after* Elli has sent the response to the
%% client. Timings contains timestamps of events like when the
%% connection was accepted, when request parsing finished, when the
%% user callback returns, etc. This allows you to collect performance
%% statistics for monitoring your app.
handle_event(request_complete, [_Request,
  _ResponseCode, _ResponseHeaders, _ResponseBody,
  _Timings], _) -> ok;

%% request_throw, request_error and request_exit events are sent if
%% the user callback code throws an exception, has an error or
%% exits. After triggering this event, a generated response is sent to
%% the user.
handle_event(request_throw, [_Request, _Exception, _Stacktrace], _) -> ok;
handle_event(request_error, [_Request, _Exception, _Stacktrace], _) -> ok;
handle_event(request_exit, [_Request, _Exception, _Stacktrace], _) -> ok;

%% invalid_return is sent if the user callback code returns a term not
%% understood by elli, see elli_http:execute_callback/1.
%% After triggering this event, a generated response is sent to the user.
handle_event(invalid_return, [_Request, _ReturnValue], _) -> ok;


%% chunk_complete fires when a chunked response is completely
%% sent. It's identical to the request_complete event, except instead
%% of the response body you get the atom "client" or "server"
%% depending on who closed the connection.
handle_event(chunk_complete, [_Request,
  _ResponseCode, _ResponseHeaders, _ClosingEnd,
  _Timings], _) -> ok;

%% request_closed is sent if the client closes the connection when
%% Elli is waiting for the next request on a keep alive connection.
handle_event(request_closed, [], _) -> ok;

%% request_timeout is sent if the client times out when
%% Elli is waiting for the request.
handle_event(request_timeout, [], _) -> ok;

%% request_parse_error fires if the request is invalid and cannot be
%% parsed by erlang:decode_packet/3 or it contains a path Elli cannot
%% parse or does not support.
handle_event(request_parse_error, [_], _) -> ok;

%% client_closed can be sent from multiple parts of the request
%% handling. It's sent when the client closes the connection or if for
%% any reason the socket is closed unexpectedly. The "Where" atom
%% tells you in which part of the request processing the closed socket
%% was detected: receiving_headers, receiving_body, before_response
handle_event(client_closed, [_Where], _) -> ok;

%% client_timeout can as with client_closed be sent from multiple
%% parts of the request handling. If Elli tries to receive data from
%% the client socket and does not receive anything within a timeout,
%% this event fires and the socket is closed.
handle_event(client_timeout, [_Where], _) -> ok;

%% bad_request is sent when Elli detects a request is not well
%% formatted or does not conform to the configured limits. Currently
%% the Reason variable can be any of the following: {too_many_headers,
%% Headers}, {body_size, ContentLength}
handle_event(bad_request, [_Reason], _) -> ok;

%% file_error is sent when the user wants to return a file as a
%% response, but for some reason it cannot be opened.
handle_event(file_error, [_ErrorReason], _) -> ok.
