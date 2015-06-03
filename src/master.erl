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
  reg:bind(node),
  ok = global:sync(),

  WorkerConfig = config:workers(),
  case whereis_master() of
    undefined ->
      ?DBG("No master found. Wait for 15 secs to become as master", []),
      {ok, #state{role = undefined, master = undefined, master_node = undefined, worker_config = WorkerConfig}, 1000};

    {Master, MasterNode} ->
      ?DBG("Detected master ~p", [Master]),
      {ok, #state{role = slave, master = Master, master_node = MasterNode, worker_config = WorkerConfig}}
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
  master_sup:start_monitors(),
  {noreply, cluster_handshake(State), rebalance_after(State#state.rebalanced)};


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
  ?DBG("Worker ~p[~p] stoped at node ~p", [Name, Pid, Node]),
  ?DBG("RuningWorkers ~p", [RuningWorkers]),
  {noreply, State#state{workers = RuningWorkers}, rebalance_after(State#state.rebalanced)};


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
  {noreply, try_become_master(State)};


handle_info({_From, {node, up, Node}}, State) when State#state.role == master ->
  ?DBG("New node has connected ~p. Send master notification", [Node]),
  {noreply, node_handshake(Node, State), rebalance_after(State#state.rebalanced)};


handle_info({_From, {node, down, Node}}, State) when State#state.role == master ->
  case lists:member(Node, State#state.worker_nodes) of
    true ->
      WorkerNodes = lists:delete(Node, State#state.worker_nodes),
      RuningWorkers = lists:filter(fun({WorkerNode, _, _}) ->
        WorkerNode =/= Node
      end, State#state.workers),
      ?DBG("Worker node ~p has down. WorkerNodes are ~p and workers are ~p", [Node, WorkerNodes, RuningWorkers]),
      
      {noreply, State#state{worker_nodes = WorkerNodes, workers = RuningWorkers}, rebalance_after(State#state.rebalanced)};

    _ ->
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
  WorkerNodes = lists:filtermap(fun({Node, IsWorker}) ->
      {IsWorker, Node}
  end, cluster:poll(is_worker)),

  ?DBG("WorkerNodes ~p", [WorkerNodes]),

  %% request list of runing workers
  RuningWorkers = lists:flatten(
    [
      [{Node, Pid, Name}
        || {Pid, Name} <- Workers]
          || {Node, Workers} <- cluster:poll(WorkerNodes, get_workers)
    ]),
  ?DBG("RuningWorkers ~p", [RuningWorkers]),

  State#state{worker_nodes = WorkerNodes, workers = RuningWorkers}.


node_handshake(Node, State) ->
  ?DBG("Start handshake with node ~p", [Node]),
  cluster:notify(Node, {master, self()}),

  case cluster:poll(Node, is_worker) of
    true ->
      WorkerNodes = State#state.worker_nodes ++ [Node],
      ?DBG("Node ~p is worker. WorkerNodes now are ~p", [Node, WorkerNodes]),

      RuningWorkers = State#state.workers ++
        [{Node, Pid, Name} || {Pid, Name} <- cluster:poll(Node, get_workers)],
      ?DBG("RuningWorkers ~p", [RuningWorkers]),

      State#state{worker_nodes = WorkerNodes, workers = RuningWorkers};

    _    ->
      ?DBG("Node ~p is not worker. Ignore it", [Node]),
      State
  end.


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
  ProcsConfig = WorkerCfg#worker.procs,

  %% nodes filtering
  AvailableNodes = case WorkerCfg#worker.nodes of
                     any -> Nodes;

                     %% filter accept nodes throung availiable nodes
                     Accept when is_list(Accept) ->
                       lists:filtermap(fun(Node) ->
                         [_, NodeHost] = string:tokens(atom_to_list(Node), "@"),
                         case lists:member(NodeHost, Accept) of
                           true -> {true, Node};
                           _ -> false
                         end
                       end, Nodes);

                     _ -> []
                   end,

  %% each_node filtering
  FreeNodes = if
                ProcsConfig#worker_procs.each_node =/= false ->
                  %% search nodes where we are not running
                  Running = [InstanceNode || {InstanceNode, _, _} <- Instances],
                  NotRunning = lists:filter(fun(Node) ->
                    not lists:member(Node, Running)
                  end, AvailableNodes),
                  %% if we are runing on all nodes than return them all
                  case NotRunning of
                    [] -> AvailableNodes;
                    N  -> N
                  end;

                true -> AvailableNodes
              end,

  %% max_per_node filtering
  RunAtNodes = if
                 ProcsConfig#worker_procs.max_per_node =/= infinity ->
                   %% calculate count of instances for each node
                   %% and filter those having more than max_per_node
                   lists:filter(fun(Node) ->
                     RunningCount = lists:foldl(fun({InstanceNode, _, _}, Acc) ->
                                                   case InstanceNode == Node of
                                                     true -> Acc + 1;
                                                     _ -> Acc
                                                   end
                                                 end, 0, Instances),

                     RunningCount < ProcsConfig#worker_procs.max_per_node
                   end, FreeNodes);


                 true -> FreeNodes
               end,

  if
    length(RunAtNodes) > 0 ->
      ?DBG("Run ~p new workers ~p on ~p", [Count, WorkerCfg#worker.name, RunAtNodes]),
      run_worker_at(WorkerCfg, Count, RunAtNodes);

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
