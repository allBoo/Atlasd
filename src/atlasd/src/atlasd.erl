%%%-------------------------------------------------------------------
%%% @author alboo
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%   this is a main API server
%%% @end
%%% Created : 29. апр 2015 0:56
%%%-------------------------------------------------------------------
-module(atlasd).
-author("alboo").

-behaviour(gen_server).
-include_lib("atlasd.hrl").

%% API
-export([
  start_link/0,
  is_worker/0,
  is_master/0,
  get_group/0,
  in_group/1,
  get_workers/1,
  get_group_workers/1,
  worker_started/1,
  worker_stoped/1,
  start_worker/1,
  start_workers/0,
  start_workers/1,
  stop_worker/1,
  stop_workers/0,
  stop_workers/1,
  restart_worker/1,
  restart_workers/0,
  restart_workers/1,
  restart_workers_hard/0,
  increase_workers/1,
  decrease_workers/1,
  change_workers_count/2,
  notify_state/2,
  get_runtime/1,
  get_nodes/0,
  connect/1,
  forget/1,
  set_workers/1,
  set_monitors/1,
  get_monitors/0,
  stop/0,
  stop_cluster/0
]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {master}).

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

%% test if node is a worker
is_worker() ->
  config:get("node.worker", false, boolean).

%% test if node is a master
is_master() ->
  config:get("node.master", false, boolean).

get_group() ->
  config:get("node.group", none, atom).



in_group(Group) when is_list(Group) ->
  in_group(list_to_atom(Group));

in_group(Group) when is_atom(Group) ->
  get_group() =:= Group.

%% start worker
start_worker(Worker) when is_record(Worker, worker); is_atom(Worker); is_list(Worker) ->
  gen_server:cast(?SERVER, {start_worker, Worker}).

start_workers() ->
  gen_server:cast(?SERVER, start_workers).

start_workers(Workers) ->
  gen_server:cast(?SERVER, {start_workers, Workers}).

%% stop worker
stop_worker(WorkerPid) when is_pid(WorkerPid) ->
  gen_server:cast(?SERVER, {stop_worker, WorkerPid}).

%% stop workers
stop_workers() ->
  gen_server:cast(?SERVER, stop_workers).

stop_workers(Workers) ->
  gen_server:cast(?SERVER, {stop_workers, Workers}).

%% restart worker
restart_worker(WorkerPid) when is_pid(WorkerPid) ->
  gen_server:cast(?SERVER, {restart_worker, WorkerPid}).

%% restart workers by name
restart_workers() ->
  gen_server:cast(?SERVER, restart_workers).

restart_workers(Workers) ->
  gen_server:cast(?SERVER, {restart_workers, Workers}).

restart_workers_hard() ->
  gen_server:cast(?SERVER, restart_workers_hard).

%% tell to master to change workers count
increase_workers(Worker) when is_record(Worker, worker); is_atom(Worker); is_list(Worker) ->
  gen_server:cast(?SERVER, {increase_workers, Worker}).

decrease_workers(Worker) when is_record(Worker, worker); is_atom(Worker); is_list(Worker) ->
  gen_server:cast(?SERVER, {decrease_workers, Worker}).

change_workers_count(Worker, Count) when is_record(Worker, worker), is_integer(Count), Count >= 0 ;
                                         is_atom(Worker), is_integer(Count), Count >= 0;
                                         is_list(Worker), is_integer(Count), Count >= 0 ->
  gen_server:cast(?SERVER, {change_workers_count, {Worker, Count}}).


%% workers must use this function to inform master about itself
worker_started({Pid, Name} = Worker) when is_pid(Pid), is_atom(Name) ->
  gen_server:cast(?SERVER, {worker_started, Worker}).

worker_stoped({Pid, Name} = Worker) when is_pid(Pid), is_atom(Name) ->
  gen_server:cast(?SERVER, {worker_stoped, Worker}).

%% get runtime config variable from master node
get_runtime(Request) ->
  gen_server:call(?SERVER, {get_runtime, Request}).

get_monitors() ->
  gen_server:call(?SERVER, get_monitors).

%% returns list of running workers
get_workers(Node) when is_list(Node) ->
  get_workers(list_to_atom(Node));
get_workers(Node) ->
  gen_server:call(?SERVER, {get_workers, Node}).

get_group_workers(Group) ->
  gen_server:call(?SERVER, {get_group_workers, Group}).

%% returns list of connected nodes
get_nodes() ->
  gen_server:call(?SERVER, get_nodes).

%% connect to a node
connect(Node) ->
  gen_server:call(?SERVER, {connect, Node}).

%% remove node from cluster
forget(Node) ->
  gen_server:call(?SERVER, {forget, Node}).

%% set new workers specification
set_workers(Workers) ->
  gen_server:call(?SERVER, {set_workers, Workers}).

%% set new monitors specification
set_monitors(Monitors) ->
  gen_server:call(?SERVER, {set_monitors, Monitors}).

%% stop current node
stop() ->
  gen_server:cast(?SERVER, stop).

stop_cluster() ->
  gen_server:cast(?SERVER, stop_cluster).

%%--------------------------------------------------------------------
%% @doc
%% notify master server about cluster state (workers stat, os stat and other)
%%
%% @spec notify_state(Type, State) -> ok
%% @end
%%--------------------------------------------------------------------
-spec(notify_state(Type :: worker_state | os_state, State :: any()) -> ok).
notify_state(Type, State) when is_atom(Type) ->
  gen_server:cast(?SERVER, {notify_state, {Type, State}}).


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
  bootstrap:start(),
  {ok, #state{master = global:whereis_name(master)}}.

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


handle_call(is_worker, _From, State) ->
  {reply, is_worker(), State};

handle_call(is_master, _From, State) ->
  {reply, is_master(), State};

handle_call(get_group, _From, State) ->
  {reply, get_group(), State};


handle_call(get_workers, _From, State) ->
  case is_worker() of
    true -> {reply, workers_sup:get_workers(), State};
    _ -> {reply, ignore, State}
  end;

handle_call({get_workers, Node}, _From, State) when is_pid(State#state.master) ->
  {reply, gen_server:call(State#state.master, {get_workers, Node}), State};
handle_call({get_workers, _Node}, _From, State) ->
  {reply, {error, "master node is not started"}, State};


handle_call({get_group_workers, Group}, _From, State) ->
  case
    in_group(Group) and is_worker() of true ->
      {reply, workers_sup:get_group_workers(Group), State};
    _ ->
      {reply, ignore, State}
  end;


handle_call(get_monitors, _From, State) when is_pid(State#state.master) ->
  {reply, gen_server:call(State#state.master, get_monitors), State};
handle_call({get_monitors, _Node}, _From, State) ->
  {reply, {error, "master node is not started"}, State};


handle_call(get_nodes, _From, State) when is_pid(State#state.master) ->
  {reply, gen_server:call(State#state.master, get_nodes), State};
handle_call(get_nodes, _From, State) ->
  {reply, {error, "master node is not started"}, State};


handle_call({get_runtime, Request}, _From, State) when is_pid(State#state.master) ->
  {reply, gen_server:call(State#state.master, {get_runtime, Request}), State};


handle_call({connect, Node}, _From, State) when is_pid(State#state.master) ->
  NodeAtom = if
               is_list(Node) -> list_to_atom(Node);
               true -> Node
             end,
  {reply, gen_server:call(State#state.master, {connect, NodeAtom}), State};
handle_call({connect, _Node}, _From, State) ->
  {reply, {error, "You should use this command only on working cluster with master nodes to connect new nodes to this cluster"}, State};


handle_call({forget, Node}, _From, State) when is_pid(State#state.master) ->
  NodeAtom = if
               is_list(Node) -> list_to_atom(Node);
               true -> Node
             end,
  {reply, gen_server:call(State#state.master, {forget, NodeAtom}), State};
handle_call({forget, _Node}, _From, State) ->
  {reply, {error, "You should use this command only on working cluster with master nodes to connect new nodes to this cluster"}, State};


handle_call({set_workers, Workers}, _From, State) when is_pid(State#state.master) ->
  {reply, gen_server:cast(State#state.master, {set_workers, Workers}), State};
handle_call({set_workers, _Workers}, _From, State) ->
  {reply, {error, "master node is not started"}, State};

handle_call({set_monitors, Monitors}, _From, State) when is_pid(State#state.master) ->
  {reply, gen_server:cast(State#state.master, {set_monitors, Monitors}), State};
handle_call({set_monitors, _Monitors}, _From, State) ->
  {reply, {error, "master node is not started"}, State};


handle_call(Request, From, State) ->
  ?DBG("Get request ~p from ~p", [Request, From]),
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

%% recieve master pid
handle_cast({master, Pid}, State) ->
  ?DBG("Recieve master pid ~p", [Pid]),
  {noreply, State#state{master = Pid}};


%% start worker
handle_cast({start_worker, Worker}, State) ->
  ?LOG("Try to start worker ~p", [Worker]),
  do_start_worker(Worker),
  {noreply, State};

handle_cast(start_workers, State) when is_pid(State#state.master) ->
  ?LOG("Try to start all workers", []),
  gen_server:cast(State#state.master, start_workers),
  {noreply, State};

handle_cast({start_workers, Workers}, State) when is_pid(State#state.master) ->
  WorkersList = lists:map(fun(El) -> if is_list(El) -> list_to_atom(El); true -> El end end, Workers),
  ?LOG("Try to start workers ~p", [WorkersList]),
  gen_server:cast(State#state.master, {start_workers, WorkersList}),
  {noreply, State};

%% stop worker
handle_cast({stop_worker, WorkerPid}, State) when is_pid(WorkerPid) ->
  ?LOG("Try to gracefully stop worker ~p", [WorkerPid]),
  do_stop_worker(WorkerPid),
  {noreply, State};

handle_cast(stop_workers, State) when is_pid(State#state.master) ->
  ?LOG("Try to gracefully stop all workers", []),
  gen_server:cast(State#state.master, stop_workers),
  {noreply, State};

handle_cast({stop_workers, Workers}, State) when is_pid(State#state.master) ->
  WorkersList = lists:map(fun(El) -> if is_list(El) -> list_to_atom(El); true -> El end end, Workers),
  ?LOG("Try to gracefully stop workers ~p", [WorkersList]),
  gen_server:cast(State#state.master, {stop_workers, WorkersList}),
  {noreply, State};

%% restart worker
handle_cast({restart_worker, WorkerPid}, State) when is_pid(WorkerPid) ->
  ?LOG("Try to gracefully restart worker ~p", [WorkerPid]),
  do_restart_worker(WorkerPid),
  {noreply, State};

handle_cast({restart_worker_hard, WorkerPid}, State) when is_pid(WorkerPid) ->
  ?LOG("Try to hard restart worker ~p", [WorkerPid]),
  do_restart_worker_hard(WorkerPid),
  {noreply, State};


handle_cast(restart_workers, State) when is_pid(State#state.master) ->
  ?LOG("Try to gracefully restart all workers", []),
  gen_server:cast(State#state.master, restart_workers),
  {noreply, State};

handle_cast({restart_workers, Workers}, State) when is_pid(State#state.master) ->
  WorkersList = lists:map(fun(El) -> if is_list(El) -> list_to_atom(El); true -> El end end, Workers),
  ?LOG("Try to gracefully restart workers ~p", [WorkersList]),
  gen_server:cast(State#state.master, {restart_workers, WorkersList}),
  {noreply, State};

handle_cast(restart_workers_hard, State) when is_pid(State#state.master) ->
  ?LOG("Try to gracefully restart all workers in hard mode", []),
  gen_server:cast(State#state.master, restart_workers_hard),
  {noreply, State};

%% increase workers count on one
handle_cast({increase_workers, Worker}, State) ->
  case resolve_worker(Worker) of
    WorkerCnf when is_record(WorkerCnf, worker) ->
      ?LOG("Try to increase workers ~p count on 1", [Worker]),
      gen_server:cast(State#state.master, {increase_workers, WorkerCnf#worker.name});
    _ ->
      neok
  end,
  {noreply, State};


%% decrease workers count on one
handle_cast({decrease_workers, Worker}, State) ->
  case resolve_worker(Worker) of
    WorkerCnf when is_record(WorkerCnf, worker) ->
      ?LOG("Try to decrease workers ~p count on 1", [Worker]),
      gen_server:cast(State#state.master, {decrease_workers, WorkerCnf#worker.name});
    _ ->
      neok
  end,
  {noreply, State};


%% change workers count
handle_cast({change_workers_count, {Worker, Count}}, State) ->
  case resolve_worker(Worker) of
    WorkerCnf when is_record(WorkerCnf, worker) ->
      ?LOG("Try to change workers ~p count to ~p", [Worker, Count]),
      gen_server:cast(State#state.master, {change_workers_count, {WorkerCnf#worker.name, Count}});
    _ ->
      neok
  end,
  {noreply, State};


%% inform master about workers
handle_cast({worker_started, {Pid, Name}}, State) when is_pid(State#state.master),
                                                       is_pid(Pid), is_atom(Name) ->
  %% set internal monitor to detect worker crash
  workers_monitor:monitor({Pid, Name}),
  gen_server:cast(State#state.master, {worker_started, {node(), Pid, Name}}),
  {noreply, State};

%% inform master about workers
handle_cast({worker_stoped, {Pid, Name}}, State) when is_pid(State#state.master),
                                                      is_pid(Pid), is_atom(Name) ->
  gen_server:cast(State#state.master, {worker_stoped, {node(), Pid, Name}}),
  {noreply, State};

%% inform master about workers
handle_cast({worker_crashed, Pid}, State) when is_pid(State#state.master),
                                               is_pid(Pid) ->
  gen_server:cast(State#state.master, {worker_crashed, {node(), Pid}}),
  {noreply, State};


%% inform master about workers
handle_cast({notify_state, {Type, Notification}}, State) when is_pid(State#state.master) ->
  gen_server:cast(State#state.master, {notify_state, node(), {Type, Notification}}),
  {noreply, State};


%% stoping the node
handle_cast(stop, State) ->
  ?LOG("Recieve request to stop node. Trying to stop node", []),
  %application:stop(atlasd),
  init:stop(),
  {noreply, State};

%% stoping whole cluster
handle_cast(stop_cluster, State) when is_pid(State#state.master) ->
  ?LOG("Recieve request to stop cluster", []),
  gen_server:cast(State#state.master, stop_cluster),
  {noreply, State};


%% undefined request
handle_cast(Request, State) ->
  ?DBG("Get notice ~p", [Request]),
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
handle_info(_Info, State) ->
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

resolve_worker(Worker) when is_atom(Worker); is_list(Worker) ->
  config:worker(Worker);
resolve_worker(Worker) when is_record(Worker, worker) ->
  Worker;
resolve_worker(_) -> false.


do_start_worker(false) -> false;
do_start_worker(Worker) when is_atom(Worker); is_list(Worker) ->
  do_start_worker(config:worker(Worker));
do_start_worker(Worker) when is_record(Worker, worker) ->
  workers_sup:start_worker(Worker);
do_start_worker(_) ->
  false.


do_stop_worker(WorkerPid) when is_pid(WorkerPid) ->
  workers_sup:stop_worker(WorkerPid);
do_stop_worker(_) ->
  false.


do_restart_worker(WorkerPid) when is_pid(WorkerPid) ->
  Worker = worker:get_config(WorkerPid),
  do_restart_worker(WorkerPid, Worker);
do_restart_worker(_) ->
  false.

do_restart_worker_hard(WorkerPid) when is_pid(WorkerPid) ->
  Worker = worker:get_config(WorkerPid),
  do_restart_worker_hard(WorkerPid, Worker);
do_restart_worker_hard(_) ->
  false.

do_restart_worker(WorkerPid, Worker) when is_pid(WorkerPid),
                                          Worker#worker.restart == disallow ->
  ?WARN("Restart of worker ~p is not allowed", [Worker#worker.name]),
  {error, disallow};

do_restart_worker(WorkerPid, Worker) when is_pid(WorkerPid),
                                          Worker#worker.restart == prestart ->
  case do_start_worker(Worker) of
    {ok, NewWorker} ->
      do_stop_worker(WorkerPid),
      {ok, NewWorker};

    {error, Error} ->
      {error, Error}
  end;

do_restart_worker(WorkerPid, Worker) when is_pid(WorkerPid) ->
  do_stop_worker(WorkerPid),
  do_start_worker(Worker).

do_restart_worker_hard(WorkerPid, Worker) when is_pid(WorkerPid) ->
  do_stop_worker(WorkerPid),
  do_start_worker(Worker).
