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
  elected/0
]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {
  role          :: master | slave | undefined,  %% current node role
  master        :: pid() | undefined,           %% master pid
  master_node   :: node() | undefined,          %% master node
  worker_config :: [#worker{}],                 %% base workers config
  worker_nodes  :: [node()],                    %% list of worker nodes
  workers       :: [{node(), pid(), Name :: atom()}]    %% current runing workers
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
      {ok, #state{role = undefined, master = undefined, master_node = undefined, worker_config = WorkerConfig}, 15000};

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
  {noreply, cluster_handshake(State)};


%% worker started on any node
handle_cast({worker_started, {Node, Pid, Name}}, State) when State#state.role == master,
                                                             is_atom(Node), is_pid(Pid), is_atom(Name) ->
  RuningWorkers = State#state.workers ++ [{Node, Pid, Name}],
  ?DBG("New worker ~p[~p] started at node ~p", [Name, Pid, Node]),
  ?DBG("RuningWorkers ~p", [RuningWorkers]),
  {noreply, State#state{workers = RuningWorkers}};

%% worker stoped on any node
handle_cast({worker_stoped, {Node, Pid, Name}}, State) when State#state.role == master,
                                                            is_atom(Node), is_pid(Pid), is_atom(Name) ->
  RuningWorkers = State#state.workers -- [{Node, Pid, Name}],
  ?DBG("Worker ~p[~p] stoped at node ~p", [Name, Pid, Node]),
  ?DBG("RuningWorkers ~p", [RuningWorkers]),
  {noreply, State#state{workers = RuningWorkers}};

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
handle_info(timeout, State) ->
  {noreply, try_become_master(State)};

%% nodes state messages
handle_info({_From, {node, _NodeStatus, _Node}}, State) when State#state.role == undefined ->
  {noreply, try_become_master(State)};

handle_info({_From, {node, down, Node}}, State) when State#state.role == slave,
                                                     State#state.master_node == Node ->
  ?DBG("Master node ~p down, try to become master", [Node]),
  {noreply, try_become_master(State)};


handle_info({_From, {node, up, Node}}, State) when State#state.role == master ->
  ?DBG("New node has connected ~p. Send master notification", [Node]),
  {noreply, node_handshake(Node, State)};


handle_info({_From, {node, down, Node}}, State) when State#state.role == master ->
  case lists:member(Node, State#state.worker_nodes) of
    true ->
      WorkerNodes = lists:delete(Node, State#state.worker_nodes),
      RuningWorkers = lists:filter(fun({WorkerNode, _, _}) ->
        WorkerNode =/= Node
      end, State#state.workers),
      ?DBG("Worker node ~p has down. WorkerNodes are ~p and workers are ~p", [Node, WorkerNodes, RuningWorkers]),
      
      {noreply, State#state{worker_nodes = WorkerNodes, workers = RuningWorkers}};

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
