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

  cluster:connect(),

  AppSup.

stop(_State) ->
  ok.
