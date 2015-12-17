%%%-------------------------------------------------------------------
%%% @author alex
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 18. Дек. 2015 20:01
%%%-------------------------------------------------------------------
-module(env).
-author("alex").
-include_lib("atlasd.hrl").

%% API
-export([
  init/0,
  get/1,
  set/2
]).


init() ->
  mnesia:create_table(env, [{disc_copies, [node()]}, {attributes, record_info(fields, env)}]).

get(Key) ->
  case mnesia:transaction(fun() -> mnesia:select(env, [{#env{key = Key, value = '$1'},[], ['$1']}]) end) of
    {atomic, [Value]} -> Value;
    Any -> Any
  end.

set(Key, Value) ->
  mnesia:transaction(fun() -> mnesia:write(#env{key = Key, value = Value}) end).

