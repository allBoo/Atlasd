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
  list/2,
  restart/2,
  stop/2
]).


get_group_workers(Options, Group) when is_list(Group)->
  get_group_workers(Options, list_to_atom(Group));

get_group_workers(Options, Group) when is_atom(Group)->
  Node = atlasctl:connect(Options),
  Response = util:rpc_call(Node, master, get_group_workers, [Group]),
  Valid = [{_Node, Workers} || {_Node, Workers} <- Response, Workers /= ignore],

  lists:flatmap(fun({N, List}) ->
                lists:map(fun({Pid, Name, _Group}) ->
                  {N, Pid, Name} end, List)
                end, Valid).

list(Options, []) ->
  list(Options, [none]);
list(Options, Args) ->
  [Group | _] = Args,
  io:format("Workers list in group ~p~n", [Group]),
  Response = get_group_workers(Options, Group),
  io:format("~p~n", [Response]).

restart(Options, Args) ->
  [Group | _] = Args,
  GroupWorkers = get_group_workers(Options, Group),
  restart(Options, GroupWorkers).

stop(Options, Args) ->
  [Group | _] = Args,
  GroupWorkers = get_group_workers(Options, Group),
  stop(Options, GroupWorkers).