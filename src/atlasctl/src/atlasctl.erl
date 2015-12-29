%%%-------------------------------------------------------------------
%%% @author alex
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 29. Дек. 2015 13:24
%%%-------------------------------------------------------------------
-module(atlasctl).
-author("alex").
-include_lib("atlasd.hrl").


-define(OPTS_SPEC, [
  {help, $h, "help", undefined, "Show the program options"},
  {config, $c, "config", string, "Path to config file for atlasd"},
  {cluster, $C, "cluster", undefined, "Atlasd cluster name"},
  {cookie, undefined, "cookie", undefined, "Cookie for a cluster"},
  {host, $h, "host", undefined, "Host with running atlasd node"},
  {list, $l, "list", undefined, "List available commands"},
  {command, undefined, undefined, string, "Command to run (e.g. nodes)"}
]).

%% API
-export([main/1]).
%% command functions
-export([
  help/2,
  nodes/2
]).


main(Args) ->
  [Options, CommandArgs] = parse_opts(Args),
  %?DBG("Options ~p", [Options]),
  %?DBG("Command args ~p", [CommandArgs]),

  execute_command(Options, CommandArgs).

err_msg(Msg) -> err_msg(Msg, []).
err_msg(Msg, Opts) ->
  io:format("ERROR: " ++ Msg ++ "~n", Opts).

dbg(Msg) -> dbg(Msg, []).
dbg(Msg, Opts) ->
  io:format("DEBUG: " ++ Msg ++ "~n", Opts).

parse_opts(Args) ->
  {ok, {Options, CommandArgs}} = getopt:parse(?OPTS_SPEC, Args),
  [Options, CommandArgs].

execute_command(Options, CommandArgs) ->
  case proplists:get_value(command, Options) of
    undefined -> help();
    X ->
      Command = list_to_atom(X),
      case erlang:function_exported(atlasctl, Command, 2) of
        true ->
          apply(atlasctl, Command, [Options, CommandArgs]);

        _ ->
          err_msg("Command ~p is not resolved", [Command])
      end
  end.

%%%===================================================================
%%% Config and cluster routine
%%%===================================================================

locate_config(undefined) -> locate_config_paths(["/etc/atlasd.yml", "etc/atlasd.yml", "/apps/atlasd/etc/atlasd.yml"]);
locate_config(Path) -> locate_config_paths([Path]).
locate_config_paths(Paths) ->
  Exists = lists:filtermap(fun(Path) ->
    case filelib:is_file(Path) and not filelib:is_dir(Path) of
      true -> {true, Path};
      _ -> false
    end
  end, Paths),
  select_config(Exists, Paths).

select_config([], Paths) ->
  err_msg("Can not locate config file on paths ~p", [Paths]),
  halt(1);
select_config(Paths, _) ->
  Path = lists:nth(1, Paths),
  dbg("Using config ~p", [Path]),
  Path.


read_config(File) ->
  lists:nth(1, yamerl_constr:file(File)).


load_config(Options) ->
  application:ensure_all_started(yamerl),
  Path = proplists:get_value(config, Options),
  Config = read_config(locate_config(Path)),
  dbg("CONFIG ~p", [Config]),
  Config.

get_and_check_value(Key, Values, Msg) ->
  Value = proplists:get_value(Key, Values),
  if
    Value == undefined ->
      err_msg(Msg),
      halt(1);
    true -> Value
  end.


connect(Options) ->
  ok = start_epmd(),

  Config = load_config(Options),
  ClusterInfo = get_and_check_value("cluster", Config, "Can not retrieve cluster config"),
  Name = get_and_check_value("name", ClusterInfo, "Can not retrieve cluster name"),
  Cookie = get_and_check_value("cookie", ClusterInfo, "Can not retrieve cluster cookie"),

  InetInfo = get_and_check_value("inet", Config, "Can not retrieve inet config"),
  Host = get_and_check_value("host", InetInfo, "Can not retrieve inet config"),

  %dbg("CLUSTER ~p", [{Node, Cookie, Host}]),
  MyNode = 'atlasctl@127.0.0.1',
  net_kernel:start([MyNode, longnames]),
  erlang:set_cookie(node(), list_to_atom(Cookie)),

  TargetNode = list_to_atom(Name ++ "@" ++ Host),

  %% See if the node is currently running  -- if it's not, we'll bail
  case {net_kernel:hidden_connect_node(TargetNode),
    net_adm:ping(TargetNode)} of
    {true, pong} ->
      ok;
    {false,pong} ->
      err_msg("Failed to connect to node ~p", [TargetNode]),
      halt(1);
    {_, pang} ->
      err_msg("Node ~p not responding to pings.", [TargetNode]),
      halt(1)
  end,
  dbg("Connected to node ~p", [TargetNode]),
  TargetNode.



start_epmd() ->
  [] = os:cmd(epmd_path() ++ " -daemon"),
  ok.

epmd_path() ->
  ErtsBinDir = filename:dirname(escript:script_name()),
  Name = "epmd",
  case os:find_executable(Name, ErtsBinDir) of
    false ->
      case os:find_executable(Name) of
        false ->
          io:format("Could not find epmd.~n"),
          halt(1);
        GlobalEpmd ->
          GlobalEpmd
      end;
    Epmd ->
      Epmd
  end.


%%%===================================================================
%%% COMMANDS
%%%===================================================================

help() -> help([], []).
help(_, _) ->
  io:format("Atlasd cli interface"),
  getopt:usage(?OPTS_SPEC, "atlasctl"),
  ok.


nodes(Options, _) ->
  Node = connect(Options),

  case rpc:call(Node, atlasd, get_nodes, []) of
    {ok, Response} ->
      io:format("List of nodes in cluster~n~p~n", [Response]);
    {error, Error} ->
      err_msg(Error);
    Error ->
      err_msg("Unknown error ~p", [Error])
  end,

  ok.
