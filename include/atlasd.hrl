%%%-------------------------------------------------------------------
%%% @author alboo
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 27. апр 2015 1:39
%%%-------------------------------------------------------------------
-author("alboo").


%%% ====================================================================
%%% Main include file
%%% ====================================================================
-include_lib("log.hrl").
-include_lib("error.hrl").

%% Helper macro for declaring children of supervisor
-define(CHILD(I), {I, {I, start_link, []}, permanent, 5000, worker, [I]}).
-define(CHILD(I, A), {I, {I, start_link, A}, permanent, 5000, worker, [I]}).
-define(CHILD_SUP(I), {I, {I, start_link, []}, permanent, infinity, supervisor, [I]}).

%%% ====================================================================
%%% Worker spec
%%% ====================================================================
-record(worker_procs, {
  min          = 1        :: integer(),
  max          = infinity :: integer() | infinity,
  allways      = 0        :: integer(),
  max_per_node = infinity :: integer() | infinity,
  each_node    = false    :: boolean()
}).

-record(worker_monitor, {
  name        :: string(),
  params = [] :: list()
}).

-record(worker, {
  name                        :: string(),
  command                     :: string(),
  priority = 0                :: integer(),
  nodes    = []               :: list(),
  restart  = simple           :: simple | disallow | prestart,
  max_mem  = infinity         :: infinity | string(),
  procs    = #worker_procs{},
  monitor  = []               :: [#worker_monitor{}]
}).

-record(worker_state, {
  name :: atom(),
  pid :: pid(),
  proc :: integer(),
  memory :: integer(),
  cpu :: float(),
  time :: integer()
}).
