%%%-------------------------------------------------------------------
%%% @author user
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 15. Дек. 2015 11:48
%%%-------------------------------------------------------------------
-module(load_monitor_test).
-author("user").

-include_lib("eunit/include/eunit.hrl").



-record(memory_info, {
  allocated_memory,
  free_memory
}).


setup_test() ->
  application:start(sasl),
  application:start(os_mon).

load_monitor_get_memory_info_test() ->
  ?assertEqual(true, is_record(monitor_os:get_memory_info(), memory_info)).