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
  %observer:start(),
  ok = start_epmd(),

  %% start worker sup
  case config:get("node.worker") of
    true ->
      atlasd_sup:start_child(?CHILD(workers_monitor)),
      atlasd_sup:start_child(?CHILD(monitor_os, [config:get("monitors.os", [{"mem_watermark", 80}])])),
      atlasd_sup:start_child(?CHILD_SUP(workers_sup));
    _ -> ok
  end,

  %% start master
  case config:get("node.master") of
    true ->
      atlasd_sup:start_child(?CHILD(db_cluster)),
      atlasd_sup:start_child(?CHILD_SUP(master_sup));
    _ -> ok
  end,

  cluster:connect(),
  AppSup.

stop(_State) ->
  ok.


%% ===================================================================
%% Private
%% ===================================================================
start_epmd() ->
  [] = os:cmd(epmd_path() ++ " -daemon"),
  ok.

epmd_path() ->
  {ok, ErtsBinDir} = file:get_cwd(),
  Name = "epmd",
  case os:find_executable(Name, ErtsBinDir) of
    false ->
      case os:find_executable(Name) of
        false ->
          ?LOG("Could not find epmd.", []),
          halt(1);
        GlobalEpmd ->
          GlobalEpmd
      end;
    Epmd ->
      Epmd
  end.
