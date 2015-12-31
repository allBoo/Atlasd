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
  rebalance/0
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
  role           :: master | slave | undefined,  %% current node role
  master         :: pid() | undefined,           %% master pid
  master_node    :: node() | undefined,          %% master node
  worker_config  :: [#worker{}],                 %% base workers config
  worker_nodes   :: [node()],                    %% list of worker nodes
  master_nodes   :: [node()],                    %% list of master nodes
  workers        :: [{node(), pid(), Name :: atom()}],    %% current runing workers
  rebalanced = 0 :: integer()
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

  case whereis_master() of
    undefined ->
      ?DBG("No master found. Wait for 15 secs to become as master", []),
      {ok, #state{role = undefined, master = undefined, master_node = undefined}, 1000};

    {Master, MasterNode} ->
      ?DBG("Detected master ~p", [Master]),
      {ok, #state{role = slave, master = Master, master_node = MasterNode}}
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
      master_node => Node =:= node(),
      is_worker   => lists:member(Node, State#state.worker_nodes),
      is_master   => lists:member(Node, State#state.master_nodes),
      stats       => statistics:get_node_stat(Node)
    }}
  end, gen_server:call(cluster, get_nodes)),
  {reply, {ok, maps:from_list(Nodes)}, State};


handle_call(_Request, _From, State) ->
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
  master_sup:start_child(?CHILD(runtime_config)),
  master_sup:start_monitors(),
  %% make rebalance event
  timer:apply_after(1000, master, rebalance, []),
  {noreply, cluster_handshake(State#state{worker_config = runtime_config:workers()})};


%% worker started on any node
handle_cast({worker_started, {Node, Pid, Name}}, State) when State#state.role == master,
                                                             is_atom(Node), is_pid(Pid), is_atom(Name) ->
  RuningWorkers = State#state.workers ++ [{Node, Pid, Name}],
  ?DBG("New worker ~p[~p] started at node ~p", [Name, Pid, Node]),
  ?DBG("RuningWorkers ~p", [RuningWorkers]),
  {noreply, State#state{workers = RuningWorkers}, rebalance_after(State#state.rebalanced)};

%% worker stoped on any node
handle_cast({worker_stoped, {Node, Pid, Name}}, State) when State#state.role == master,
                                                            is_atom(Node), is_pid(Pid), is_atom(Name) ->
  RuningWorkers = State#state.workers -- [{Node, Pid, Name}],
  statistics:forget(Node, Name, Pid),
  ?DBG("Worker ~p[~p] stoped at node ~p", [Name, Pid, Node]),
  ?DBG("RuningWorkers ~p", [RuningWorkers]),
  {noreply, State#state{workers = RuningWorkers}, rebalance_after(State#state.rebalanced)};


%% change workers count
handle_cast({change_workers_count, {WorkerName, Count}}, State) when State#state.role == master,
                                                                     is_atom(WorkerName), is_integer(Count), Count >= 0 ->
  WorkerConfig = change_worker_procs_count(State#state.worker_config, WorkerName, Count),

  {noreply, State#state{worker_config = WorkerConfig}, rebalance_after(State#state.rebalanced)};


%% change workers count
handle_cast({increase_workers, WorkerName}, State) when State#state.role == master,
                                                        is_atom(WorkerName) ->
  Instances = get_worker_instances(WorkerName, State#state.workers),
  InstancesCount = length(Instances),
  WorkerConfig = change_worker_procs_count(State#state.worker_config, WorkerName, InstancesCount + 1),

  {noreply, State#state{worker_config = WorkerConfig}, rebalance_after(State#state.rebalanced)};


%% change workers count
handle_cast({decrease_workers, WorkerName}, State) when State#state.role == master,
  is_atom(WorkerName) ->
  Instances = get_worker_instances(WorkerName, State#state.workers),
  InstancesCount = case length(Instances) of
                     X when X > 0 -> X - 1;
                     _ -> 0
                   end ,
  WorkerConfig = change_worker_procs_count(State#state.worker_config, WorkerName, InstancesCount),

  {noreply, State#state{worker_config = WorkerConfig}, rebalance_after(State#state.rebalanced)};


%% Recieve notifications
handle_cast({notify_state, Node, {worker_state, WorkerState}}, State) when State#state.role == master, is_record(WorkerState, worker_state) ->
  statistics:worker_state(Node, WorkerState),
  {noreply, State};


handle_cast({notify_state, Node, {emergency_state, []}}, State) when State#state.role == master ->
  case reg:find({oom_killer, Node}) of
    undefined ->
      {ok, OomKiller} = supervisor:start_child(master_sup, ?CHILD(oom_killer, [Node]));
    OomKiller ->
      OomKiller
  end,
  gen_fsm:send_event(OomKiller, kill),
  {noreply, State};


handle_cast({notify_state, Node, {os_state, OsState}}, State) when State#state.role == master, is_record(OsState, os_state) ->
  statistics:os_state(Node, OsState),
  {noreply, State};


%% REBALANCE cluster state
handle_cast(rebalance, State) when State#state.role == master ->
  {noreply, do_rebalance(State)};

%%
handle_cast(_Request, State) ->
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
  {noreply, State};


%% nodes state messages
handle_info({_From, {node, _NodeStatus, _Node}}, State) when State#state.role == undefined ->
  {noreply, try_become_master(State)};

handle_info({_From, {node, down, Node}}, State) when State#state.role == slave,
                                                     State#state.master_node == Node ->
  ?DBG("Master node ~p down, try to become master", [Node]),
  statistics:forget(Node),
  {noreply, try_become_master(State)};


handle_info({_From, {node, up, Node}}, State) when State#state.role == master ->
  ?DBG("New node has connected ~p. Send master notification", [Node]),
  {noreply, node_handshake(Node, State), rebalance_after(State#state.rebalanced)};


handle_info({_From, {node, down, Node}}, State) when State#state.role == master ->
  statistics:forget(Node),

  IsMaster = lists:member(Node, State#state.master_nodes),
  IsWorker = lists:member(Node, State#state.worker_nodes),

  if
    IsMaster =:= true ->
      MasterNodes = lists:delete(Node, State#state.master_nodes),
      {noreply, State#state{master_nodes = MasterNodes}, rebalance_after(State#state.rebalanced)};
    IsWorker =:= true ->
      WorkerNodes = lists:delete(Node, State#state.worker_nodes),
      RuningWorkers = lists:filter(fun({WorkerNode, _, _}) ->
        WorkerNode =/= Node
                                   end, State#state.workers),
      ?DBG("Worker node ~p has down. WorkerNodes are ~p and workers are ~p", [Node, WorkerNodes, RuningWorkers]),

      {noreply, State#state{worker_nodes = WorkerNodes, workers = RuningWorkers}, rebalance_after(State#state.rebalanced)};
    true ->
      {noreply, State}
  end;

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
terminate(_Reason, _State) ->
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
  case global:register_name(?MODULE, self()) of
    yes ->
      ?DBG("Elected as master ~p [~p]", [node(), self()]),
      elected(),
      State#state{role = master, master = self()};

    no  ->
      {Master, MasterNode} = whereis_master(),
      ?DBG("Detected master ~p", [Master]),
      State#state{role = slave,  master = Master, master_node = MasterNode}
  end.

whereis_master() ->
  case global:whereis_name(?MODULE) of
    undefined -> undefined;
    Pid -> {Pid, node(Pid)}
  end.


cluster_handshake(State) ->
  ?DBG("Start handshake with nodes", []),
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

  State#state{worker_nodes = WorkerNodes, workers = RuningWorkers, master_nodes = MasterNodes}.


node_handshake(Node, State) ->
  ?DBG("Start handshake with node ~p", [Node]),
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
      WorkerNodes = State#state.worker_nodes
  end,

  State#state{master_nodes = MasterNodes, worker_nodes = WorkerNodes}.


%% rebalancing
rebalance_after(LastRebalanced) when LastRebalanced == 0 ->
  ?REBALANCE;

rebalance_after(LastRebalanced) ->
  LastRun = timer:now_diff(os:timestamp(), LastRebalanced),
  if
    LastRun > ?MAX_REBALANCE ->
      rebalance(),
      ?REBALANCE;
    true -> ?REBALANCE
  end.


do_rebalance(State) ->
  ?DBG("REBALANCE CLUSTER", []),
  %% ensure all workers are runing
  ensure_runing(State#state.worker_config, State#state.workers, State#state.worker_nodes),
  State#state{rebalanced = os:timestamp()}.


ensure_runing([], _, _) ->
  ok;

ensure_runing([WorkerCfg | WorkersConfig], Workers, Nodes) ->
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

  Instances = get_worker_instances(WorkerCfg#worker.name, Workers),
  InstancesCount = length(Instances),
  if
    (InstancesCount >= MinInstances) and (InstancesCount =< MaxInstances) -> ok;

    InstancesCount < MinInstances ->
      NewCount = MinInstances - InstancesCount,
      ?DBG("Count instances of ~p id lower than ~p",
        [WorkerCfg#worker.name, MinInstances]),
      run_workers(NewCount, WorkerCfg, Instances, Nodes);

    InstancesCount > MaxInstances ->
      KillCount = InstancesCount - MaxInstances,
      ?DBG("Count instances of ~p id higher than ~p",
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
      ?LOG("Can not find proper nodes for worker ~p", [WorkerCfg#worker.name]),
      error
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
      stop_worker_at(WorkerCfg, Count, StopWorkers);

    true ->
      ?LOG("Can't find proper nodes to stop worker ~p", [WorkerCfg#worker.name]),
      error
  end.


stop_worker_at(_, _, []) ->
  ok;

stop_worker_at(_, 0, _Instances) ->
  ok;

stop_worker_at(Worker, Count, [{Node, WorkerPid, _} | Instances]) ->
  cluster:notify(Node, {stop_worker, WorkerPid}),
  stop_worker_at(Worker, Count - 1, Instances).


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
