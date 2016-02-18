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
  {verbose, $v, "verbose", string, "Show debug information"},
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
  connect/1,
  help/2,
  verbose/2,
  nodes/2,
  connect/2,
  forget/2,
  workers/2,
  monitors/2,
  get_runtime/2,

  %% nodetool commands
  getpid/2,
  ping/2,
  stop/2,
  stop_cluster/2,
  restart/2,
  reboot/2
]).


main(Args) ->
  [Options, CommandArgs] = parse_opts(Args),
  %?DBG("Options ~p", [Options]),
  %?DBG("Command args ~p", [CommandArgs]),

  execute(Options, CommandArgs).

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
      util:err_msg("Command ~p is not resolved", [Command])
  end;
execute_command(_, _) -> ok.

%%%===================================================================
%%% Config and cluster routine
%%%===================================================================

locate_config(undefined) -> locate_config_paths(["/etc/atlasd/atlasd.yml", "etc/atlasd.yml",
  "../etc/atlasd.yml", "/apps/atlasd/etc/atlasd.yml"]);
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
  util:err_msg("Can not locate config file on paths ~p", [Paths]),
  halt(1);
select_config(Paths, _) ->
  Path = lists:nth(1, Paths),
  util:dbg("Using config ~p", [Path]),
  Path.


read_config(File) ->
  lists:nth(1, yamerl_constr:file(File)).


load_config(Options) ->
  application:ensure_all_started(yamerl),
  Path = proplists:get_value(config, Options),
  Config = read_config(locate_config(Path)),
  util:dbg("CONFIG ~p", [Config]),
  Config.

get_and_check_value(Key, Values, Msg) ->
  Value = proplists:get_value(Key, Values),
  if
    Value == undefined ->
      util:err_msg(Msg),
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
      util:err_msg("Failed to connect to node ~p", [TargetNode]),
      halt(1);
    {_, pang} ->
      util:err_msg("Node ~p not responding to pings.", [TargetNode]),
      halt(1)
  end,
  util:dbg("Connected to node ~p", [TargetNode]),
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
%%% NODETOOL COMMANDS
%%%===================================================================

getpid(Options, _) ->
  Node = connect(Options),
  io:format("~p\n",
    [list_to_integer(rpc:call(Node, os, getpid, []))]),
  ok.

ping(Options, _) ->
  connect(Options),
  io:format("pong\n"),
  ok.

stop(Options, _) ->
  Node = connect(Options),
  io:format("~p\n", [util:rpc_call(Node, stop, [])]),
  ok.

stop_cluster(Options, _) ->
  Node = connect(Options),
  io:format("~p\n", [util:rpc_call(Node, stop_cluster, [])]),
  ok.

restart(Options, _) ->
  Node = connect(Options),
  io:format("~p\n", [rpc:call(Node, init, restart, [], 60000)]),
  ok.

reboot(Options, _) ->
  Node = connect(Options),
  io:format("~p\n", [rpc:call(Node, init, reboot, [], 60000)]),
  ok.

%%%===================================================================
%%% COMMANDS
%%%===================================================================

help() -> help([], []).
help(_, _) ->
  io:format("Atlasd cli interface~n"),
  getopt:usage(?OPTS_SPEC, "atlasctl"),
  ok.

verbose(_, _) ->
  util:show_debug(),
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

  Response = util:rpc_call(Node, get_nodes, []),
  io:format("List of nodes in cluster~n~p~n", [Response]),
  ok.

connect(Options, Args) ->
  util:dbg("Options ~p~n", [Options]),
  util:dbg("Args ~p~n", [Args]),

  case Args of
    [TargetNode | _] ->
      Node = connect(Options),
      io:format("Trying to connect to node ~p~n", [TargetNode]),
      case util:rpc_call(Node, connect, [TargetNode]) of
        ok -> io:format("New node ~p is successfully connected to a cluster~n", [TargetNode]);
        Response -> io:format("~p", [Response])
      end;

    _ ->
      util:err_msg("You should pass the node connect to~n")
  end,

  ok.


forget(Options, Args) ->
  case Args of
    [TargetNode | _] ->
      Node = connect(Options),
      io:format("Trying to forget node ~p~n", [TargetNode]),
      case util:rpc_call(Node, forget, [TargetNode]) of
        ok -> io:format("Node ~p is successfully removed from a cluster~n", [TargetNode]);
        Response -> io:format("~p", [Response])
      end;

    _ ->
      util:err_msg("You should pass the node connect to~n")
  end,

  ok.


workers(_Options, []) ->
  io:format("Available options are: list, log, config, export, import, restart, stop~n");
workers(Options, Args) ->
  [Cmd | CmdArgs] = Args,
  case list_to_atom(Cmd) of
    list -> workers:list(Options, CmdArgs);
    group_list -> workers:group_list(Options, CmdArgs);
    log -> workers:log(Options, CmdArgs);
    config -> workers:config(Options, CmdArgs);
    export -> workers:export(Options, CmdArgs);
    import -> workers:import(Options, CmdArgs);
    restart -> workers:restart(Options, CmdArgs);
    restart_group -> workers:restart_group(Options, CmdArgs);
    stop_group -> workers:stop_group(Options, CmdArgs);
    stop  -> workers:stop(Options, CmdArgs);
    start  -> workers:start(Options, CmdArgs);

    E ->
      util:err_msg("Unknown workers command ~p", [E])
  end,
  ok.

monitors(_Options, []) ->
  io:format("Available options are: config, export, import~n");
monitors(Options, Args) ->
  [Cmd | CmdArgs] = Args,
  case list_to_atom(Cmd) of
    list -> monitors:list(Options, CmdArgs);
    config -> monitors:config(Options, CmdArgs);
    export -> monitors:export(Options, CmdArgs);
    import -> monitors:import(Options, CmdArgs);

    E ->
      util:err_msg("Unknown monitors command ~p", [E])
  end,
  ok.

get_runtime(_Options, []) ->
  util:err_msg("Empty config key");
get_runtime(Options, Args) ->
  [ConfigKey | _] = Args,
  Node = atlasctl:connect(Options),
  util:rpc_call(Node, get_runtime, [ConfigKey]).

