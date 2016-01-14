%%%-------------------------------------------------------------------
%%% @author alex
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 18. Дек. 2015 20:15
%%%-------------------------------------------------------------------
-module(migration_2).
-author("alex").
-include_lib("atlasd.hrl").

%% API
-export([
  up/0
]).

up() ->
  mnesia:create_table(monitor, [{disc_copies, [node()]}, {attributes, record_info(fields, monitor)}]),
  insert([
    #monitor{
      name = monitor_rabbitmq,
      config = #rabbitmq_monitor{
        host = "***REMOVED***",
        tasks = [
          #rabbitmq_monitor_task{
            task = "task-listen-middle",
            queue = "ds.conveyor.converter.gc"
          },
          #rabbitmq_monitor_task{
            task = "task-listen-low",
            queue = "ds.conveyor.all.low"
          },
          #rabbitmq_monitor_task{
            task = "task-listen-high",
            queue = "ds.conveyor.all.high"
          }
        ]
      }
    }
  ]).

insert([]) -> ok;
insert([Item | Items]) ->
  mnesia:transaction(fun() -> mnesia:write(Item) end),
  insert(Items).
