%%%-------------------------------------------------------------------
%%% @author p1
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 25. Февр. 2016 16:51
%%%-------------------------------------------------------------------
-module(groups).
-include_lib("atlasd.hrl").

%% API
-export([
  list/3,
  restart/2,
  stop/2,
  start/2,
  modify/4,
  create/3
]).

get_group_workers(Options, Group) when is_list(Group)->
  get_group_workers(Options, list_to_atom(Group));

get_group_workers(Options, Group) when is_atom(Group)->
  Node = atlasctl:connect(Options),
  util:rpc_call(Node, get_group_workers, [Group]).

get_group_nodes(Options, Group) when is_list(Group)->
  get_group_nodes(Options, list_to_atom(Group));

get_group_nodes(Options, Group) when is_atom(Group)->
  Node = atlasctl:connect(Options),
  util:rpc_call(Node, get_group_nodes, [Group]).

modify(Options, Args, Action, Type) ->
  [Group | Names] = Args,
  Node = atlasctl:connect(Options),
  io:format("~p ~p ~p group ~p~n", [Action, Type, Names, Group]),
  Response = util:rpc_call(Node, modify_groups, [Group, Names, Action, Type]),
  io:format("~p~n", [Response]).

get_matches(Names, Regex) ->
  lists:map(fun(Name) ->
              ListName = if
                           is_atom(Name) ->
                             atom_to_list(Name);
                           true ->
                             Name
                         end,
              case re:run(ListName, Regex, [{capture,none}]) of
                match ->
                  ListName;
                _ ->
                  nomatch
              end
            end, Names).

create(Options, Args, Type) ->
  [Regex| _] = Args,
  Node = atlasctl:connect(Options),
  Names = case Type of
    workers ->
      Response = util:rpc_call(Node, get_workers_config, []),
      io:format("~p~n", [Response]),
      lists:map(fun(W) ->
                   W#worker.name
                end, Response);
    nodes ->
      Response = util:rpc_call(Node, get_nodes, []),
      maps:keys(Response)
  end,

  Result = util:rpc_call(Node, modify_groups, [Regex, get_matches(Names, Regex), add, Type]),
  io:format("~p~n", [Result]).


list(Options, [], workers) ->
  list(Options, [none], workers);
list(Options, Args, workers) ->
  [Group | _] = Args,
  io:format("Workers list in group ~p~n", [Group]),
  Response = get_group_workers(Options, Group),
  io:format("~p~n", [Response]);

list(Options, Args, nodes) ->
  [Group | _] = Args,
  io:format("Nodes list in group ~p~n", [Group]),
  Response = get_group_nodes(Options, Group),
  io:format("~p~n", [Response]).

restart(Options, Args) ->
  [Group | _] = Args,
  Node = atlasctl:connect(Options),
  GroupWorkers = get_group_workers(Options, Group),
  Response = util:rpc_call(Node, restart_workers, [GroupWorkers]),
  io:format("~p~n", [Response]).

stop(Options, Args) ->
  [Group | _] = Args,
  Node = atlasctl:connect(Options),
  GroupWorkers = get_group_workers(Options, Group),
  Response = util:rpc_call(Node, stop_workers, [GroupWorkers]),
  io:format("~p~n", [Response]).


start(Options, []) ->
  Node = atlasctl:connect(Options),
  io:format("Start all workers for all groups ~n", []),
  Response = util:rpc_call(Node, start_group_workers, [all]),
  io:format("~p~n", [Response]);

start(Options, Args) ->
  [Group | _] = Args,
  Node = atlasctl:connect(Options),
  io:format("Start workers in group ~p~n", [Group]),
  Response = util:rpc_call(Node, start_group_workers, [Group]),
  io:format("~p~n", [Response]).