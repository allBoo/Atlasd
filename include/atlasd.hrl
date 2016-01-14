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
-include_lib("stdlib/include/qlc.hrl").

%% Helper macro for declaring children of supervisor
-define(CHILD(I), {I, {I, start_link, []}, permanent, 5000, worker, [I]}).
-define(CHILD(I, A), {I, {I, start_link, A}, permanent, 5000, worker, [I]}).
-define(CHILD_SUP(I), {I, {I, start_link, []}, permanent, infinity, supervisor, [I]}).
-define(CHILD_SUP_T(I), {I, {I, start_link, []}, transient, infinity, supervisor, [I]}).

%%% ====================================================================
%%% Env spec
%%% ====================================================================
-record(env, {
  key,
  value
}).

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
  monitor  = []               :: [#worker_monitor{}],
  enabled  = true             :: boolean()
}).

-record(rabbitmq_monitor_task, {
  task :: string(),
  exchange = parsley :: parsley | atom(),
  queue :: string(),
  vhost = "%2f",
  minutes_to_add_consumers = 1000
}).

-record(rabbitmq_monitor, {
  mode = api :: api | native | atom(),
  host :: string(),
  port = "15672",
  user = "guest" :: string(),
  pass = "guest" :: string(),
  tasks = [] :: [#rabbitmq_monitor_task{}]
}).

%%-record(os_monitor, {
%%  mem_watermark = 80 :: integer()
%%}).

-record(monitor, {
  name :: atom(),
  config :: #rabbitmq_monitor{}
}).


%%% ====================================================================
%%% OS monitor spec
%%% ====================================================================
-record(worker_state, {
  name         :: atom(),
  pid          :: pid(),
  proc         :: integer(),
  memory = 0   :: integer(),
  cpu    = 0.0 :: float(),
  uptime = 0   :: integer()
}).

-record(avg_worker, {
  cpu = [] :: [],
  mem = [] :: [],
  avg_cpu = 0.0 :: float(),
  avg_mem = 0 :: integer()
}).

-record(cpu_info, {
  load_average = 0.0 :: float(),
  per_cpu = []
}).

-record(memory_info, {
  allocated_memory = 0 :: integer(),
  free_memory      = 0 :: integer()
}).

-record(os_state, {
  memory_info = #memory_info{} :: #memory_info{},
  cpu_info    = #cpu_info{}    :: #cpu_info{},
  overloaded  = false          :: boolean()
}).

