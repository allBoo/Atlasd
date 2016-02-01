%%%-------------------------------------------------------------------
%%% @author alex
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 21. Янв. 2016 14:41
%%%-------------------------------------------------------------------
-module(workers).
-author("alex").
-include_lib("atlasd.hrl").

%% API
-export([
  list/2,
  restart/2,
  start/2,
  stop/2,
  config/2,
  export/2,
  import/2,
  log/2
]).



list(Options, []) ->
  list(Options, [all]);
list(Options, Args) ->
  [TargetNode | _] = Args,
  Node = atlasctl:connect(Options),
  io:format("Workers list on node ~p~n", [TargetNode]),
  Response = util:rpc_call(Node, master, get_workers, [TargetNode]),
  io:format("~p~n", [Response]).

log(_Options, []) ->
  util:err_msg("You should pass the worker~n");
log(Options, Args) ->
  [TargetWorker | _] = Args,
  Node = atlasctl:connect(Options),
  Workers = util:rpc_call(Node, master, get_workers, [all]),

  WorkersNodes = lists:filtermap(fun({N, Ws}) ->
    FoundedWorkers = lists:filter(
      fun({P, _}) ->
        TargetWorker == pid_to_list(P)
      end, Ws),
    case length(FoundedWorkers) of
      1 ->
        {true, {N, lists:nth(1, FoundedWorkers)}};
      _ -> false
    end
  end, Workers),

  case length(WorkersNodes) of
    1 ->
      {WorkerNode, {WorkerPid, _}} = lists:nth(1, WorkersNodes),
      S = self(),
      F = fun(N) -> S ! N end,
      rpc:call(WorkerNode, worker, set_log_handler, [WorkerPid, F, atlasctl]),
      loop();
    _ ->
      util:err_msg("No worker found for that pid ~n")
  end,
  ok.

loop() ->
  receive
    Msg ->
      util:dbg("Message ~p", [Msg]),
      loop()
  end.

restart(Options, []) ->
  Node = atlasctl:connect(Options),
  io:format("Soft Restart all workers on all nodes", []),
  Response = util:rpc_call(Node, restart_workers, []),
  io:format("~p~n", [Response]);
restart(Options, ["hard" | _]) ->
  Node = atlasctl:connect(Options),
  io:format("Hard Restart all workers on all nodes", []),
  Response = util:rpc_call(Node, restart_workers_hard, []),
  io:format("~p~n", [Response]);
restart(Options, Workers) ->
  Node = atlasctl:connect(Options),
  io:format("Restart workers ~p on all nodes", [Workers]),
  Response = util:rpc_call(Node, restart_workers, [Workers]),
  io:format("~p~n", [Response]).


stop(Options, []) ->
  Node = atlasctl:connect(Options),
  io:format("Stop all workers on all nodes", []),
  Response = util:rpc_call(Node, stop_workers, []),
  io:format("~p~n", [Response]);
stop(Options, Workers) ->
  Node = atlasctl:connect(Options),
  io:format("Stop workers ~p on all nodes", [Workers]),
  Response = util:rpc_call(Node, stop_workers, [Workers]),
  io:format("~p~n", [Response]).


start(Options, []) ->
  Node = atlasctl:connect(Options),
  io:format("Start all workers on all nodes", []),
  Response = util:rpc_call(Node, start_workers, []),
  io:format("~p~n", [Response]);
start(Options, Workers) ->
  Node = atlasctl:connect(Options),
  io:format("Start workers ~p on all nodes", [Workers]),
  Response = util:rpc_call(Node, start_workers, [Workers]),
  io:format("~p~n", [Response]).


config(Options, _Args) ->
  io:format("Worker config values:~n", []),
  Config = atlasctl:get_runtime(Options, [get_workers]),
  io:format("~p~n", [Config]).

export(Options, []) ->
  export(Options, [json]);
export(Options, Args) ->
  [Format | _] = Args,
  Config = atlasctl:get_runtime(Options, [get_workers]),
  Formatted = format(Config, list_to_atom(Format)),
  io:format("~p~n", [Formatted]).

format(Config, map) ->
  ProcsPrinter = ?record_to_map(worker_procs),
  MonitorPrinter = ?record_to_map(worker_monitor),
  MonitorsPrinter = fun(Monitors) ->
                      lists:map(fun(El) ->
                                  MonitorPrinter(El)
                                end,
                      Monitors)
                    end,
  WorkerPrinter = ?record_to_map(worker),
  lists:map(fun(El) ->
    El0 = WorkerPrinter(El),
    El1 = maps:put(monitor, MonitorsPrinter(maps:get(monitor, El0)), El0),
    maps:put(procs, ProcsPrinter(maps:get(procs, El0)), El1)
  end, Config);

format(Config, json) ->
  Map = format(Config, map),

  jiffy:encode(Map).


import(_Options, []) ->
  util:err_msg("You must provide path to file or raw json");
import(Options, Args) ->
  [Arg | _] = Args,
  RawData = case filelib:is_file(Arg) of
              true ->
                {ok, Contents} = file:read_file(Arg),
                binary_to_list(Contents);

              _ -> Arg
            end,

  Data = jiffy:decode(RawData, [return_maps]),
  Workers = create_workers_spec(Data),
  util:dbg("loaded workers spec ~p~n", [Workers]),

  Node = atlasctl:connect(Options),
  io:format("Trying to setup new workers spec~n"),
  ok = util:rpc_call(Node, set_workers, [Workers]).


create_workers_spec(Data) ->
  create_workers_spec(Data, []).

create_workers_spec([], Acc) -> Acc;
create_workers_spec([Item | Tail], Acc) ->
  Worker = #worker{
    name     = binary_to_atom(maps:get(<<"name">>, Item), utf8),
    command  = binary_to_list(maps:get(<<"command">>, Item)),
    nodes    = format_nodes(maps:get(<<"nodes">>, Item, any)),
    enabled  = format_boolean(maps:get(<<"enabled">>, Item, true)),
    max_mem  = format_mem(maps:get(<<"max_mem">>, Item, infinity)),
    priority = format_integer(maps:get(<<"priority">>, Item, 0)),
    restart  = binary_to_atom(maps:get(<<"restart">>, Item, simple), utf8),
    procs    = format_procs(maps:get(<<"procs">>, Item)),
    monitor  = maps:get(<<"monitor">>, Item)
  },
  [Worker | create_workers_spec(Tail, Acc)].

format_nodes(<<"any">>) -> any;
format_nodes(Bin) -> binary_to_list(Bin).

format_boolean(X) when is_boolean(X) -> X;
format_boolean(<<"true">>) -> true;
format_boolean(_) -> false.

format_mem(<<infinity>>) -> infinity;
format_mem(Bin) -> binary_to_list(Bin).

format_integer(X) when is_integer(X) -> X;
format_integer(X) -> binary_to_integer(X).

format_inf_integer(infinity) -> infinity;
format_inf_integer(<<infinity>>) -> infinity;
format_inf_integer(X) when is_integer(X) -> X;
format_inf_integer(X) -> binary_to_integer(X).

format_procs(ProcsBin) ->
  #worker_procs{
    allways      = format_integer(maps:get(<<"allways">>, ProcsBin, 0)),
    each_node    = format_boolean(maps:get(<<"each_node">>, ProcsBin, false)),
    max          = format_inf_integer(maps:get(<<"max">>, ProcsBin, infinity)),
    max_per_node = format_inf_integer(maps:get(<<"max_per_node">>, ProcsBin, infinity)),
    min          = format_integer(maps:get(<<"min">>, ProcsBin, 0))
  }.
