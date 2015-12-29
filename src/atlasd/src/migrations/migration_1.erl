%%%-------------------------------------------------------------------
%%% @author alex
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 18. Дек. 2015 20:15
%%%-------------------------------------------------------------------
-module(migration_1).
-author("alex").
-include_lib("atlasd.hrl").

%% API
-export([
  up/0
]).


up() ->
  mnesia:create_table(worker, [{disc_copies, [node()]}, {attributes, record_info(fields, worker)}]),
  insert([
    #worker{
      name = 'task-listen-low',
      command = "/apps/atlasd/priv/command1.sh",
      priority = 100,
      nodes = ["192.168.2.1"],
      restart = disallow,
      procs = #worker_procs{min = 1}
    },
    #worker{
      name = 'task-listen-middle',
      command = "/apps/atlasd/priv/command2.sh",
      priority = 100,
      nodes = any,
      restart = simple,
      max_mem = "100M",
      procs = #worker_procs{min = 1, max = 15, max_per_node = 1}
    },
    #worker{
      name = 'task-listen-high',
      command = "/apps/atlasd/priv/command3.sh",
      priority = 1,
      nodes = ["192.168.2.1","192.168.2.5"],
      restart = prestart,
      max_mem = "100M",
      procs = #worker_procs{min = 1, each_node = 1}
    }
  ]).

insert([]) -> ok;
insert([Item | Items]) ->
  mnesia:transaction(fun() -> mnesia:write(Item) end),
  insert(Items).
