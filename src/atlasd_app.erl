-module(atlasd_app).

-behaviour(application).
-include_lib("atlasd.hrl").

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
  AppSup = atlasd_sup:start_link(),
  observer:start(),

  %% start worker sup
  case config:get("node.worker") of
    true ->
      supervisor:start_child(atlasd_sup, ?CHILD(workers_monitor)),
      supervisor:start_child(atlasd_sup, ?CHILD_SUP(workers_sup));
    _ -> ok
  end,

  %% start master
  case config:get("node.master") of
    true -> supervisor:start_child(atlasd_sup, ?CHILD_SUP(master_sup));
    _ -> ok
  end,

  %% start http-server
  {ok, IPTupled}  = inet_parse:address(config:get("http.host")),
  HttpAttr = [
    {callback, api},
    {ip, IPTupled},
    {port, config:get("http.port")},
    {min_acceptors, 5} % стандартно там 20, если что
  ],
  config:get("http.enabled") andalso supervisor:start_child(atlasd_sup, ?CHILD(elli, [HttpAttr])),

  cluster:connect(),

  AppSup.

stop(_State) ->
  ok.
