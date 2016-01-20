%%%-------------------------------------------------------------------
%%% @author alex
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 21. Янв. 2016 14:42
%%%-------------------------------------------------------------------
-module(util).
-author("alex").

%% API
-export([
  err_msg/1,
  err_msg/2,
  dbg/1,
  dbg/2,
  rpc_call/3,
  rpc_call/4
]).



err_msg(Msg) -> err_msg(Msg, []).
err_msg(Msg, Opts) ->
  io:format("ERROR: " ++ Msg ++ "~n", Opts).

dbg(Msg) -> dbg(Msg, []).
dbg(Msg, Opts) ->
  io:format("DEBUG: " ++ Msg ++ "~n", Opts).

rpc_call(Node, Module, Action, Args) ->
  case rpc:call(Node, Module, Action, Args) of
    {ok, Response} -> Response;
    {error, Error} ->
      err_msg(Error),
      halt(1);
    Any -> Any
  end.

rpc_call(Node, Action, Args) ->
  rpc_call(Node, atlasd, Action, Args).
