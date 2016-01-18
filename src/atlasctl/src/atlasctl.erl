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
  {list, $l, "list", undefined, "List available commands"},
  {config, $c, "config", string, "Path to config file for atlasd"},
  {cluster, $C, "cluster", string, "Atlasd cluster name"},
  {host, $h, "host", string, "Host with running atlasd node"},
  {cookie, undefined, "cookie", string, "Cookie for a cluster"},
  {command, undefined, undefined, string, "Command to run (e.g. nodes)"}
]).

%% API
-export([main/1]).
%% command functions
-export([
  help/2,
  nodes/2,
  connect/2,
  forget/2,
  worker_log/2
]).


main(Args) ->
  [Options, CommandArgs] = parse_opts(Args),
  %?DBG("Options ~p", [Options]),
  %?DBG("Command args ~p", [CommandArgs]),

  execute(Options, CommandArgs).

err_msg(Msg) -> err_msg(Msg, []).
err_msg(Msg, Opts) ->
  io:format("ERROR: " ++ Msg ++ "~n", Opts).

dbg(Msg) -> dbg(Msg, []).
dbg(Msg, Opts) ->
  io:format("DEBUG: " ++ Msg ++ "~n", Opts).

parse_opts(Args) ->
  {ok, {Options, CommandArgs}} = getopt:parse(?OPTS_SPEC, Args),
  [Options, CommandArgs].

execute(Options, CommandArgs) -> execute(Options, CommandArgs, Options).

execute([], _, _) -> ok;
execute([Option | Options], CommandArgs, AllOptions) ->
  case execute_command(Option, [AllOptions, CommandArgs]) of
    ok -> execute(Options, CommandArgs, AllOptions);
    _ -> ok
  end.

execute_command(help, _) -> help(), stop;
execute_command(list, _) -> list(), stop;
execute_command({command, X}, [Options, CommandArgs]) ->
  Command = list_to_atom(X),
  case erlang:function_exported(atlasctl, Command, 2) of
    true ->
      apply(atlasctl, Command, [Options, CommandArgs]);

    _ ->
      err_msg("Command ~p is not resolved", [Command])
  end;
execute_command(_, _) -> ok.

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
  io:format("Atlasd cli interface~n"),
  getopt:usage(?OPTS_SPEC, "atlasctl"),
  ok.

list() -> list([], []).
list(_, _) ->
  io:format("Atlasd cli interface~n"),
  io:format("List of available commands~n"),
  io:format("  help\t\tShow the program options~n"),
  io:format("  nodes\t\tList nodes in a cluster~n"),
  io:format("  connect\tConnect newly created node to a cluster~n"),
  ok.


nodes(Options, _) ->
  Node = connect(Options),

  Response = rpc_call(Node, get_nodes, []),
  io:format("List of nodes in cluster~n~p~n", [Response]),
  ok.

connect(Options, Args) ->
  dbg("Options ~p~n", [Options]),
  dbg("Args ~p~n", [Args]),

  case Args of
    [TargetNode | _] ->
      Node = connect(Options),
      io:format("Trying to connect to node ~p~n", [TargetNode]),
      case rpc_call(Node, connect, [TargetNode]) of
        ok -> io:format("New node ~p is successfully connected to a cluster~n", [TargetNode]);
        Response -> io:format("~p", [Response])
      end;

    _ ->
      err_msg("You should pass the node connect to~n")
  end,

  ok.


forget(Options, Args) ->
  case Args of
    [TargetNode | _] ->
      Node = connect(Options),
      io:format("Trying to forget node ~p~n", [TargetNode]),
      case rpc_call(Node, forget, [TargetNode]) of
        ok -> io:format("Node ~p is successfully removed from a cluster~n", [TargetNode]);
        Response -> io:format("~p", [Response])
      end;

    _ ->
      err_msg("You should pass the node connect to~n")
  end,

  ok.

worker_log(Options, Args) ->
  case Args of
    [TargetWorker | _] ->
      connect(Options),
      WorkerPid = list_to_pid(TargetWorker),
      TargetNode = node(WorkerPid),
      dbg("Node ~p workers ~p~n",[TargetNode, rpc:call(TargetNode, workers_sup, get_workers, [])]),
      S = self(),
      F = fun(N) -> S ! N end,
      rpc:call(TargetNode, worker, set_log_handler, [WorkerPid, F, atlasctl]),
      loop();
    _ ->
      err_msg("You should pass the worker~n")
  end,

  ok.

loop() ->
  receive
    Msg ->
      dbg("Message ~p", [Msg]),
      loop()
  end.

%%%===================================================================
%%% RPC
%%%===================================================================

rpc_call(Node, Action, Args) ->
  case rpc:call(Node, atlasd, Action, Args) of
    {ok, Response} -> Response;
    {error, Error} ->
      err_msg(Error),
      halt(1);
    Error ->
      err_msg("Unknown error '~p'", [Error]),
      halt(1)
  end.
