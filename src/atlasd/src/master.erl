%%%-------------------------------------------------------------------
%%% @author alboo
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 28. апр 2015 1:27
%%%-------------------------------------------------------------------
-module(master).
-author("alboo").

-behaviour(gen_server).
-include_lib("atlasd.hrl").

%% API
-export([
  start_link/0,
  elected/0,
  rebalance/0,
  resolve_master/3,

  get_workers/1,
  get_group_workers/1,
  whereis_master/0,
  get_worker_instances/1,
  get_monitors/0
]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).
-define(REBALANCE, 5000). %% milliseconds
-define(MAX_REBALANCE, 15000000). %% microseconds

-record(state, {
  role           = undefined :: master | slave | undefined,  %% current node role
  master         = undefined :: pid() | undefined,           %% master pid
  master_node    = undefined :: node() | undefined,          %% master node
  worker_config  = []        :: [#worker{}],                 %% base workers config
  worker_nodes   = []        :: [node()],                    %% list of worker nodes
  master_nodes   = []        :: [node()],                    %% list of master nodes
  group_nodes    = []        :: [],                    %% list of group nodes
  workers        = []        :: [{node(), pid(), Name :: atom()}],    %% current runing workers
  rebalanced     = 0         :: integer(),
  rebalancer     = undefined :: timer:tref() | undefined,
  priority       = 0         :: integer()
}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).


elected() ->
  gen_server:cast(?SERVER, elected).


rebalance() ->
  gen_server:cast(?SERVER, rebalance).


%% returns list of running workers
get_workers(Node) when is_list(Node) ->
  get_workers(list_to_atom(Node));
get_workers(Node) ->
  gen_server:call(?SERVER, {get_workers, Node}).

get_group_workers(Group) ->
  gen_server:call(?SERVER, {get_group_workers, Group}).

get_worker_instances(Worker) when is_list(Worker) ->
  get_worker_instances(list_to_atom(Worker));
get_worker_instances(Worker) when is_atom(Worker) ->
  gen_server:call(?SERVER, {get_worker_instances, Worker}).

get_monitors() ->
  gen_server:call(?SERVER, get_monitors).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
  {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([]) ->
  db_cluster:start_slave(),
  reg:bind(node),
  ok = global:sync(),

  %master_sup:stop_child(master_monitors_sup),
  %master_sup:stop_child(runtime_config),

  cluster:connect(),

  NodePriority = config:get('node.priority', 0, integer),
  case whereis_master() of
    undefined ->
      ?LOG("No master found. Wait for cluster connection finished", []),
      {ok, #state{role = undefined, master = undefined, master_node = undefined, priority = NodePriority}};

    {Master, MasterNode} ->
      ?LOG("Detected master ~p", [Master]),
      {ok, #state{role = slave, master = Master, master_node = MasterNode, priority = NodePriority}}
  end.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
  {reply, Reply :: term(), NewState :: #state{}} |
  {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
  {stop, Reason :: term(), NewState :: #state{}}).

handle_call({get_runtime, Request}, _From, State) when State#state.role == master ->
  {reply, gen_server:call(runtime_config, Request), State};


handle_call(get_nodes, _From, State) when State#state.role == master ->
  Nodes = lists:map(fun(Node) ->
    {Node, #{
      name        => Node,
      group       => atlasd:get_group(),
      master_node => Node =:= node(),
      is_worker   => lists:member(Node, State#state.worker_nodes),
      is_master   => lists:member(Node, State#state.master_nodes),
      stats       => statistics:get_node_stat(Node, printable)
    }}
  end, gen_server:call(cluster, get_nodes)),
  {reply, {ok, maps:from_list(Nodes)}, State};


handle_call({get_workers, all}, _From, State) ->
  Workers = cluster:poll(get_workers),
  {reply, {ok, Workers}, State};
handle_call({get_workers, Node}, _From, State) ->
  Workers = cluster:poll(Node, get_workers),
  {reply, {ok, Workers}, State};

handle_call({get_group_workers, Group}, _From, State) ->
  Workers = cluster:poll({get_group_workers, Group}),
  {reply, {ok, Workers}, State};

handle_call(get_monitors, _From, State) ->
  {reply, master_monitors_sup:get_running_monitors(), State};

handle_call({get_worker_instances, Worker}, _From, State) ->
  Instances = lists:filter(
    fun({_, _, Name}) ->
      Name == Worker
    end, State#state.workers),
  {reply, Instances, State};

handle_call({connect, Node}, _From, State) when State#state.role == master ->
  {reply, {ok, cluster:add_node(Node)}, State};

handle_call({forget, Node}, _From, State) when State#state.role == master ->
  {reply, {ok, cluster:forget_node(Node)}, State};


handle_call(Request, _From, State) ->
  ?DBG("Unknown call to master ~p", [Request]),
  {reply, ok, State}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).

%% i am a master ^_^
handle_cast(elected, State) ->
  db_cluster:start_master(),
  master_sup:start_child(runtime_config),
  master_sup:start_global_child(master_monitors_sup),
  master_sup:start_global_child(cluster_monitor),
  %% make rebalance event
  timer:apply_after(1000, master, rebalance, []),
  {noreply, cluster_handshake(State#state{worker_config = runtime_config:workers()})};


%% worker started on any node
handle_cast({worker_started, {Node, Pid, Name}}, State) when State#state.role == master,
                                                             is_atom(Node), is_pid(Pid), is_atom(Name) ->
  RuningWorkers = State#state.workers ++ [{Node, Pid, Name}],
  ?LOG("New worker ~p[~p] started at node ~p", [Name, Pid, Node]),
  ?DBG("RuningWorkers ~p", [RuningWorkers]),
  {noreply, rebalance_after(State#state{workers = RuningWorkers})};

%% worker stoped on any node
handle_cast({worker_stoped, {Node, Pid, Name}}, State) when State#state.role == master,
                                                            is_atom(Node), is_pid(Pid), is_atom(Name) ->
  RuningWorkers = State#state.workers -- [{Node, Pid, Name}],
  statistics:forget(Node, Name, Pid),
  ?LOG("Worker ~p[~p] stoped at node ~p", [Name, Pid, Node]),
  ?DBG("RuningWorkers ~p", [RuningWorkers]),
  {noreply, rebalance_after(State#state{workers = RuningWorkers})};


%% change workers count
handle_cast({change_workers_count, {WorkerName, Count}}, State) when State#state.role == master,
                                                                     is_atom(WorkerName), is_integer(Count), Count >= 0 ->
  WorkerConfig = change_worker_procs_count(State#state.worker_config, WorkerName, Count),

  {noreply, rebalance_after(State#state{worker_config = WorkerConfig})};


%% change workers count
handle_cast({increase_workers, WorkerName}, State) when State#state.role == master,
                                                        is_atom(WorkerName) ->
  Instances = get_worker_instances(WorkerName, State#state.workers),
  InstancesCount = length(Instances),
  WorkerConfig = change_worker_procs_count(State#state.worker_config, WorkerName, InstancesCount + 1),

  {noreply, rebalance_after(State#state{worker_config = WorkerConfig})};


%% change workers count
handle_cast({decrease_workers, WorkerName}, State) when State#state.role == master,
  is_atom(WorkerName) ->
  Instances = get_worker_instances(WorkerName, State#state.workers),
  InstancesCount = case length(Instances) of
                     X when X > 0 -> X - 1;
                     _ -> 0
                   end ,
  WorkerConfig = change_worker_procs_count(State#state.worker_config, WorkerName, InstancesCount),

  {noreply, rebalance_after(State#state{worker_config = WorkerConfig})};


%% set new workers config
handle_cast({set_workers, Workers}, State) when State#state.role == master ->
  ?LOG("Trying to setup new workers config ~p", [Workers]),
  %% TODO make group operations
  [runtime_config:delete(W) || W <- runtime_config:workers()],
  [runtime_config:set_worker(W) || W <- Workers],
  {noreply, do_rebalance(State#state{worker_config = runtime_config:workers()})};

%% set new monitors config
handle_cast({set_monitors, Monitors}, State) when State#state.role == master ->
  ?LOG("Trying to setup new monitors config ~p", [Monitors]),
  %% TODO make group operations
  [runtime_config:delete(M) || M <- runtime_config:monitors()],
  [runtime_config:set_monitor(M) || M <- Monitors],
  master_sup:start_global_child(master_monitors_sup),
  {noreply, State};


%% start workers on all nodes
handle_cast(start_workers, State) when State#state.role == master ->
  Config = lists:map(fun(Worker) -> Worker#worker{enabled = true} end, State#state.worker_config),
  {noreply, rebalance_after(State#state{worker_config = Config})};

handle_cast({start_workers, Workers}, State) when State#state.role == master ->
  Config = lists:map(fun(Worker) ->
                       case lists:member(Worker#worker.name, Workers) of
                         true -> Worker#worker{enabled = true};
                         _ -> Worker
                       end
                     end, State#state.worker_config),
  {noreply, rebalance_after(State#state{worker_config = Config})};


%% stop workers on all nodes
handle_cast(stop_workers, State) when State#state.role == master ->
  do_stop_workers(State#state.workers),
  Config = lists:map(fun(Worker) -> Worker#worker{enabled = false} end, State#state.worker_config),
  {noreply, State#state{worker_config = Config}};

handle_cast({stop_workers, Workers}, State) when State#state.role == master ->
  Running = lists:filter(fun({_, _, Name}) -> lists:member(Name, Workers) end, State#state.workers),
  Config = lists:map(fun(Worker) ->
                       case lists:member(Worker#worker.name, Workers) of
                         true -> Worker#worker{enabled = false};
                         _ -> Worker
                       end
                     end, State#state.worker_config),
  do_stop_workers(Running),
  {noreply, State#state{worker_config = Config}};

%% restart workers on all nodes
handle_cast(restart_workers, State) when State#state.role == master ->
  do_restart_workers(State#state.workers),
  {noreply, State};

handle_cast({restart_workers, Workers}, State) when State#state.role == master ->
  Running = lists:filter(fun({_, _, Name}) -> lists:member(Name, Workers) end, State#state.workers),
  do_restart_workers(Running),
  {noreply, State};

handle_cast(restart_workers_hard, State) when State#state.role == master ->
  do_restart_workers_hard(State#state.workers),
  {noreply, State};


%% Recieve notifications
handle_cast({notify_state, Node, {worker_state, WorkerState}}, State) when State#state.role == master, is_record(WorkerState, worker_state) ->
  statistics:worker_state(Node, WorkerState),
  {noreply, State};


handle_cast({notify_state, Node, {emergency_state, []}}, State) when State#state.role == master ->
  Name = {oom_killer, Node},
  case reg:find(Name) of
    undefined ->
      {ok, OomKiller} = supervisor:start_child(master_sup, ?CHILD(Name, oom_killer, [Node]));
    OomKiller ->
      OomKiller
  end,
  gen_fsm:send_event(OomKiller, kill),
  {noreply, State};


handle_cast({notify_state, Node, {os_state, OsState}}, State) when State#state.role == master, is_record(OsState, os_state) ->
  statistics:os_state(Node, OsState),
  {noreply, State};

%% stop whole cluster
handle_cast(stop_cluster, State) when State#state.role == master ->
  cluster:notify(stop),
  {noreply, State};

%% REBALANCE cluster state
handle_cast(rebalance, State) when State#state.role == master ->
  {noreply, do_rebalance(State)};

%%
handle_cast(Request, State) ->
  ?DBG("Unknown cast to master ~p", [Request]),
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).

%% not recieved messages within 15secs after start
%% try to become as master
handle_info(timeout, State) when State#state.role == undefined ->
  {noreply, try_become_master(State)};


%% rebalance required
handle_info(timeout, State) when State#state.role == master ->
  rebalance(),
  {noreply, State, ?REBALANCE};

%% cluster connected
handle_info({_From, connected}, State) when State#state.role == undefined ->
  ?LOG("Cluster is connected. Trying to become as a master"),
  {noreply, try_become_master(State)};

%% nodes state messages
handle_info({_From, {node, _NodeStatus, _Node}}, State) when State#state.role == undefined ->
  {noreply, State};


handle_info({_From, {node, up, Node}}, State) when State#state.role == master ->
  ?LOG("New node has connected ~p. Send master notification", [Node]),
  {noreply, rebalance_after(node_handshake(Node, State))};


handle_info({_From, {node, down, Node}}, State) when State#state.role == slave,
                                                     State#state.master_node == Node ->
  ?LOG("Master node ~p down, try to become master", [Node]),
  statistics:forget(Node),
  {noreply, try_become_master(State)};


handle_info({_From, {node, down, Node}}, State) when State#state.role == master ->
  statistics:forget(Node),

  case lists:member(Node, State#state.master_nodes) of
    true ->
      MasterNodes = lists:delete(Node, State#state.master_nodes);
    _ ->
      MasterNodes = State#state.master_nodes
  end,

  case lists:member(Node, State#state.worker_nodes) of
    true ->
      WorkerNodes = lists:delete(Node, State#state.worker_nodes),
      RunningWorkers = lists:filter(fun({WorkerNode, _, _}) ->
        WorkerNode =/= Node
                                   end, State#state.workers),
      ?LOG("Worker node ~p has down. WorkerNodes are ~p", [Node, WorkerNodes]);
    _ ->
      WorkerNodes = State#state.worker_nodes,
      RunningWorkers = State#state.workers
  end,

  {noreply, rebalance_after(State#state{worker_nodes = WorkerNodes, workers = RunningWorkers, master_nodes = MasterNodes})};


handle_info(Info, State) ->
  ?DBG("MASTER RECIEVE ~p", [Info]),
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(Reason, _State) ->
  ?WARN("MASTER IS TERMINATING WITH REASON ~p", [Reason]),
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
  {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

try_become_master(State) ->
  case global:register_name(?MODULE, self(), fun resolve_master/3) of
    yes ->
      ?LOG("Elected as master ~p [~p]", [node(), self()]),
      elected(),
      State#state{role = master, master = self()};

    no  ->
      {Master, MasterNode} = whereis_master(),
      ?LOG("Detected master ~p", [Master]),
      State#state{role = slave,  master = Master, master_node = MasterNode}
  end.

whereis_master() ->
  case global:whereis_name(?MODULE) of
    undefined -> undefined;
    Pid -> {Pid, node(Pid)}
  end.


resolve_master(Name, Pid1, Pid2) ->
  Priority1 = (sys:get_state(Pid1))#state.priority,
  Priority2 = (sys:get_state(Pid2))#state.priority,
  {Min, Max} = if
                 Priority1 < Priority2 -> {Pid1, Pid2};
                 true -> {Pid2, Pid1}
               end,
  ?WARN("Master conflict. Terminating ~w\n", [{Name, Min}]),
  exit(Min, kill),
  Max.


cluster_handshake(State) ->
  ?LOG("Start handshake with cluster", []),
  %% send notification to all
  cluster:notify({master, self()}),

  %% get info about all nodes
  MasterNodes = lists:filtermap(fun({Node, IsMaster}) ->
    if
      IsMaster -> {IsMaster, Node};
      true -> false
    end
  end, cluster:poll(is_master)),

  WorkerNodes = lists:filtermap(fun({Node, IsWorker}) ->
      if
        IsWorker -> {IsWorker, Node};
        true -> false
      end
  end, cluster:poll(is_worker)),

  ?DBG("Worker nodes are ~p", [WorkerNodes]),
  ?DBG("Master nodes are ~p", [MasterNodes]),

  %% connect master nodes to database cluster
  db_cluster:add_nodes(MasterNodes),

  %% request list of runing workers
  RuningWorkers = lists:flatten(
    [
      [{Node, Pid, Name}
        || {Pid, Name} <- Workers]
          || {Node, Workers} <- cluster:poll(WorkerNodes, get_workers)
    ]),
  ?DBG("Runing workers are ~p", [RuningWorkers]),

  GroupNodes = lists:map(fun(X) ->
                            {cluster:poll(X, get_group), X}
                         end, lists:usort(WorkerNodes ++ MasterNodes)),
  ?DBG("GroupNodes  are ~p", [GroupNodes]),
  State#state{worker_nodes = WorkerNodes, workers = RuningWorkers, master_nodes = MasterNodes, group_nodes = GroupNodes}.


node_handshake(Node, State) ->
  ?LOG("Start handshake with node ~p", [Node]),
  cluster:notify(Node, {master, self()}),


  case cluster:poll(Node, is_master) of
    true ->
      ?DBG("Node ~p is a master node. Connect it as a slave", [Node]),
      db_cluster:add_nodes([Node]),
      MasterNodes = State#state.master_nodes ++ [Node];
    _   ->
      ?DBG("Node ~p is not a master node. Ignore it", [Node]),
      MasterNodes = State#state.master_nodes
  end,

  case cluster:poll(Node, is_worker) of
    true ->
      WorkerNodes = State#state.worker_nodes ++ [Node],
      ?DBG("Node ~p is a worker. WorkerNodes now are ~p", [Node, WorkerNodes]),
      RuningWorkers = State#state.workers ++
        [{Node, Pid, Name} || {Pid, Name} <- cluster:poll(Node, get_workers)],
      ?DBG("RuningWorkers ~p", [RuningWorkers]);

    _    ->
      ?DBG("Node ~p is not a worker. Ignore it", [Node]),
      WorkerNodes = State#state.worker_nodes,
      RuningWorkers = State#state.workers
  end,

  GroupNodes = State#state.group_nodes ++ {cluster:poll(Node, get_group), Node},

  State#state{master_nodes = MasterNodes, worker_nodes = WorkerNodes, workers = RuningWorkers, group_nodes = lists:usort(GroupNodes)}.


%% rebalancing
rebalance_after(State) ->
  Time = get_rebalance_after(State#state.rebalanced),

  State#state.rebalancer =/= undefined andalso
    timer:cancel(State#state.rebalancer),

  {ok, Rebalancer} = if
                       Time > 0 -> timer:apply_after(Time, master, rebalance, []);
                       true ->
                         rebalance(),
                         {ok, undefined}
                     end,

  State#state{rebalancer = Rebalancer}.

get_rebalance_after(0) ->
  ?REBALANCE;

get_rebalance_after(Rebalanced) ->
  LastRun = timer:now_diff(os:timestamp(), Rebalanced),
  if
    LastRun > ?MAX_REBALANCE -> 0;
    true -> ?REBALANCE
  end.


do_rebalance(State) ->
  ?DBG("REBALANCE CLUSTER", []),
  %% ensure there are no unknown workers
  ensure_all_known(State#state.worker_config, State#state.workers),
  %% ensure all workers are runing
  ?DBG("Ensure runing", []),
  ensure_runing(State#state.worker_config, State#state.workers, State#state.group_nodes),
  State#state{rebalanced = os:timestamp()}.


ensure_all_known(WorkersConfig, Workers) ->
  KnownWorkersNames = [Worker#worker.name || Worker <- WorkersConfig, Worker#worker.enabled == true],
  UnknownWorkers = lists:filter(fun({_Node, _Pid, Name}) ->
                                  not lists:member(Name, KnownWorkersNames)
                                end, Workers),

  length(UnknownWorkers) > 0 andalso
      ?DBG("There are unknown workers in a cluster. List of unknown workers: ~p", [UnknownWorkers]),

  do_stop_workers(UnknownWorkers).


ensure_runing([], _, _) ->
  ok;

ensure_runing([WorkerCfg | WorkersConfig], Workers, Nodes) when WorkerCfg#worker.enabled =/= true ->
  ensure_runing(WorkersConfig, Workers, Nodes);

ensure_runing([WorkerCfg | WorkersConfig], Workers, Nodes) when WorkerCfg#worker.enabled == true ->
  ProcsConfig = WorkerCfg#worker.procs,

  %% static instances count
  [MinInstances, MaxInstances] = if
                                   ProcsConfig#worker_procs.each_node =/= false ->
                                     Max = if
                                             is_integer(ProcsConfig#worker_procs.max)
                                             and ProcsConfig#worker_procs.max > length(Nodes) ->
                                               ProcsConfig#worker_procs.max;

                                             true ->
                                               length(Nodes)
                                           end,
                                     [length(Nodes), Max];

                                   ProcsConfig#worker_procs.allways > 0 ->
                                     [ProcsConfig#worker_procs.allways, ProcsConfig#worker_procs.allways];

                                   true ->
                                     [ProcsConfig#worker_procs.min, ProcsConfig#worker_procs.max]
                                 end,

  Instances = get_worker_instances_sorted_by_cpu(WorkerCfg#worker.name, Workers),
  InstancesCount = length(Instances),
  if
    (InstancesCount >= MinInstances) and (InstancesCount =< MaxInstances) -> ok;

    InstancesCount < MinInstances ->
      NewCount = MinInstances - InstancesCount,
      ?DBG("Count instances of ~p is lower than ~p", [WorkerCfg#worker.name, MinInstances]),
      GroupNodes = [Node || {Group, Node} <- Nodes, Group =:= WorkerCfg#worker.group],
      case length(GroupNodes) of
        X when X == 0 -> ?DBG("No nodes available in group ~p ~p", [WorkerCfg#worker.group, Nodes]);
        _ -> run_workers(NewCount, WorkerCfg, Instances, GroupNodes, Workers)
      end;


    InstancesCount > MaxInstances ->
      KillCount = InstancesCount - MaxInstances,
      ?DBG("Count instances of ~p is higher than ~p",
        [WorkerCfg#worker.name, MaxInstances]),
      stop_workers(KillCount, WorkerCfg, Instances)
  end,
  ensure_runing(WorkersConfig, Workers, Nodes).


%% run number of new workers
run_workers(Count, WorkerCfg, Instances, Nodes) ->
  AvailableNodes = master_utils:filter_nodes(WorkerCfg, Instances, Nodes),

  if
    length(AvailableNodes) > 0 ->
      ?DBG("Run ~p new workers ~p on ~p", [Count, WorkerCfg#worker.name, AvailableNodes]),
      run_worker_at(WorkerCfg, Count, AvailableNodes);

    true ->
      ?WARN("Can not find proper nodes for worker ~p", [WorkerCfg#worker.name]),
      error
  end.

%% run number of new workers
run_workers(Count, WorkerCfg, Instances, Nodes, Workers) ->
  AvailableNodes = master_utils:filter_nodes(WorkerCfg, Instances, Nodes),
  ?DBG("get_node_for_worker ~w", [get_node_for_worker(Nodes, WorkerCfg, Workers, Count)]),
  if
    length(AvailableNodes) > 0 ->
      ?DBG("Run ~p new workers ~p on ~p", [Count, WorkerCfg#worker.name, AvailableNodes]),
      run_worker_at(WorkerCfg, Count, AvailableNodes);

    true ->
      ?WARN("Can not find proper nodes for worker ~p, looking for low priority workers", [WorkerCfg#worker.name]),
      case get_node_for_worker(Nodes, WorkerCfg, Workers, Count) of
        [{Node, Instances} | _Tail] ->
          lists:foreach(fun(W) ->
                            do_stop_worker(W)
                        end, Instances),
          run_worker_at(WorkerCfg, Count, [Node]);
        _ ->
          error
      end
  end.

run_worker_at(_, _, []) ->
  error;

run_worker_at(_, 0, _Nodes) ->
  ok;

run_worker_at(Worker, Count, Nodes) ->
  NodeIndex = (Count rem length(Nodes)) + 1,
  Node = lists:nth(NodeIndex, Nodes),
  cluster:notify(Node, {start_worker, Worker}),
  run_worker_at(Worker, Count - 1, Nodes).


%% stop number of workers
stop_workers(Count, WorkerCfg, Instances) ->
  StopWorkers = case WorkerCfg#worker.nodes of
                  Accept when is_list(Accept), length(Accept) > 0 ->
                    %% search improper nodes
                    N = lists:filtermap(fun({InstanceNode, _, _} = Instance) ->
                          [_, InstanceHost] = string:tokens(atom_to_list(InstanceNode), "@"),
                          case lists:member(InstanceHost, WorkerCfg#worker.nodes) of
                            false -> {true, Instance};
                            _ -> false
                          end
                        end, Instances),
                    case N of
                      [] -> Instances;
                      L  -> L
                    end;

                  _ -> Instances
                end,

  if
    length(StopWorkers) > 0 ->

      ?DBG("Stop ~p workers ~p on ~p", [Count, WorkerCfg#worker.name, StopWorkers]),
      stop_worker_at(Count, StopWorkers);

    true ->
      ?WARN("Can't find proper nodes to stop worker ~p", [WorkerCfg#worker.name]),
      error
  end.


stop_worker_at(_, []) ->
  ok;

stop_worker_at(0, _Instances) ->
  ok;

stop_worker_at(Count, [Worker | Instances]) ->
  do_stop_worker(Worker),
  stop_worker_at(Count - 1, Instances).


do_stop_worker({Node, Pid, Name}) ->
  ?LOG("Trying to stop worker ~p (~p) on node ~p", [Name, Pid, Node]),
  cluster:notify(Node, {stop_worker, Pid}).


do_stop_workers([]) -> ok;
do_stop_workers([Worker | Workers]) ->
  do_stop_worker(Worker),
  do_stop_workers(Workers).


get_node_for_worker(Nodes, WorkerCfg, Workers, Count) ->
  WorkerAvgStat = statistics:get_worker_avg_stat(WorkerCfg#worker.name),
  LPWorkers = lists:filter(fun({_,_,Name}) ->
        Conf = config:worker(Name),
        Conf#worker.priority < WorkerCfg#worker.priority
      end, Workers),
  WorkersStates = get_workers_states(LPWorkers),
  {WStat, _WOStat} = lists:partition(fun(WS) -> tuple_size(WS) == 4 end, WorkersStates),
  F1 = fun(El1, El2) -> length(element(2, El1)) < element(2, El2) end,
  lists:sort(F1, lists:filtermap(fun(Node) ->
                            F = fun({_,_,_,X}, {_,_,_,Y}) -> X#worker_state.memory > Y#worker_state.memory end,
                            NodeWorkerStates = lists:sort(F, lists:filter(fun({N,_,_,_})->
                                N == Node
                            end, WStat)),
                            {EnoughWorkers, _Acc} = lists:mapfoldl(fun({N,P,Nm,S}, Acc) ->
                                case S#worker_state.memory of
                                  X when Acc < (WorkerAvgStat#avg_worker.avg_mem*Count) ->
                                    {{true, {N, P, Nm}}, Acc+X};
                                 _ -> {false, Acc}
                               end
                           end, 0, NodeWorkerStates),
                            case length(EnoughWorkers) > 0 of
                              true ->
                                {true, {Node, lists:filtermap(fun(El) -> El end, EnoughWorkers)}};
                              _ ->
                                false
                            end
                         end, Nodes)).

get_workers_states(Workers) ->
  Statistics = statistics:get_all_workers(),
  lists:map(fun({Node, WorkerPid, Name}) ->
                  try
                    case is_map(Statistics) andalso nested:get([Node, Name, WorkerPid], Statistics, []) of
                      X when is_record(X, worker_state)  ->
                        {Node, WorkerPid, Name, X};
                      _ ->
                        {Node, WorkerPid, Name}
                    end
                  catch
                    _:_ ->
                    {Node, WorkerPid, Name}
                  end
            end, Workers).

get_worker_instances_sorted_by_cpu(WorkerName, Workers) ->
  WorkersStates = lists:filter(fun(WS) ->
                      element(3, WS) == WorkerName
                 end, get_workers_states(Workers)),
  {WStat, WOStat} = lists:partition(fun(WS) -> tuple_size(WS) == 4 end, WorkersStates),
  Sorted = case WStat of
             Z when length(Z) > 0 ->
               F = fun({_,_,_,X}, {_,_,_,Y}) -> X#worker_state.cpu < Y#worker_state.cpu end,
               lists:map(fun({Node, Pid, Worker, _}) -> {Node, Pid, Worker} end, lists:sort(F, Z));
             _ -> []
           end,
  lists:append(Sorted, WOStat).


%% return list of worker instances
get_worker_instances(WorkerName, WorkersList) ->
  lists:filter(fun({_Node, _Pid, Name}) ->
    Name == WorkerName
  end, WorkersList).

%% change worker min and max procs count in config
change_worker_procs_count(WorkersConfig, WorkerName, Count) ->
  lists:map(fun(Worker) ->
              Procs = if
                        Worker#worker.name == WorkerName ->
                          (Worker#worker.procs)#worker_procs{min = Count, max = Count};
                        true -> Worker#worker.procs
                      end,
              Worker#worker{procs = Procs}
            end,
    WorkersConfig).


do_restart_worker({Node, Pid, Name}) ->
  ?LOG("Trying to restart worker ~p (~p) on node ~p", [Name, Pid, Node]),
  cluster:notify(Node, {restart_worker, Pid}).

do_restart_workers([]) -> ok;
do_restart_workers([Worker | Workers]) ->
  do_restart_worker(Worker),
  do_restart_workers(Workers).

do_restart_workers_hard([]) -> ok;
do_restart_workers_hard([{Node, Pid, Name} | Workers]) ->
  ?LOG("Trying to hard restart worker ~p (~p) on node ~p", [Name, Pid, Node]),
  cluster:notify(Node, {restart_worker_hard, Pid}),
  do_restart_workers_hard(Workers).
