%%%-------------------------------------------------------------------
%%% @author alex
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 15. Дек. 2015 16:10
%%%-------------------------------------------------------------------
-module(master_utils).
-author("alex").
-include_lib("atlasd.hrl").

%% API
-export([
  filter_nodes/3
]).

%% private
-export([
  filter_config_nodes/1, filter_each_node_nodes/1, filter_max_per_node_nodes/1, filter_overload_nodes/1
]).

%%%===================================================================
%%% API
%%%===================================================================

filter_nodes(Worker, Instances, Nodes) ->
  Filters = [filter_config_nodes, filter_each_node_nodes, filter_max_per_node_nodes, filter_overload_nodes],
  do_filter_nodes(Filters, {Worker, Instances, Nodes}).

%%%===================================================================
%%% Internal functions
%%%===================================================================

do_filter_nodes([F | Funs], {Worker, Instances, _Nodes} = Args) ->
  ?DBG("CALL ~p WITH ARGS ~p", [F, Args]),
  case ?MODULE:F(Args) of
    {error, Error} -> {error, Error};
    [] -> [];
    ResultNodes -> do_filter_nodes(Funs, {Worker, Instances, ResultNodes})
  end;
do_filter_nodes([], {_Worker, _Instances, Nodes}) ->
  Nodes.


filter_config_nodes({Worker, _Instances, Nodes}) ->
  case Worker#worker.nodes of
    any -> Nodes;

    %% filter accept nodes throung availiable nodes
    Accept when is_list(Accept) ->
      lists:filtermap(fun(Node) ->
                        [_, NodeHost] = string:tokens(atom_to_list(Node), "@"),
                        case lists:member(NodeHost, Accept) of
                          true -> {true, Node};
                          _ -> false
                        end
                      end, Nodes);

    _ -> []
  end.

filter_each_node_nodes({Worker, Instances, Nodes}) ->
  ProcsConfig = Worker#worker.procs,
  if
    ProcsConfig#worker_procs.each_node =/= false ->
      %% search nodes where we are not running
      Running = [InstanceNode || {InstanceNode, _, _} <- Instances],
      NotRunning = lists:filter(fun(Node) ->
        not lists:member(Node, Running)
                                end, Nodes),
      %% if we are runing on all nodes than return them all
      case NotRunning of
        [] -> Nodes;
        N  -> N
      end;

    true -> Nodes
  end.

filter_max_per_node_nodes({Worker, Instances, Nodes}) ->
  ProcsConfig = Worker#worker.procs,
  if
    ProcsConfig#worker_procs.max_per_node =/= infinity ->
      %% calculate count of instances for each node
      %% and filter those having more than max_per_node
      lists:filter(fun(Node) ->
                      RunningCount = lists:foldl(fun({InstanceNode, _, _}, Acc) ->
                                                    case InstanceNode == Node of
                                                      true -> Acc + 1;
                                                      _ -> Acc
                                                    end
                                                 end, 0, Instances),

                      RunningCount < ProcsConfig#worker_procs.max_per_node
                   end, Nodes);


    true -> Nodes
  end.

filter_overload_nodes({Worker, _Instances, Nodes}) ->
  NodesStat = statistics:get_nodes_stat(Nodes),
  WorkerStat = statistics:get_worker_avg_stat(Worker#worker.name),

  lists:filter(fun(Node) ->
    NodeStat = nested:get([Node], NodesStat, #os_state{}),
    MemInfo = NodeStat#os_state.memory_info,
    CpuInfo = NodeStat#os_state.cpu_info,

    NodeStat#os_state.overloaded =:= false andalso
      MemInfo#memory_info.free_memory + WorkerStat#avg_worker.avg_mem =< MemInfo#memory_info.allocated_memory andalso
        CpuInfo#cpu_info.load_average =< length(CpuInfo#cpu_info.per_cpu) * 2
  end, Nodes).
