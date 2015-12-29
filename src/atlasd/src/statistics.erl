%%%-------------------------------------------------------------------
%%% @author alex
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 14. Дек. 2015 18:43
%%%-------------------------------------------------------------------
-module(statistics).
-author("alex").

-behaviour(gen_server).
-include_lib("atlasd.hrl").

%% API
-export([
  start_link/0,
  worker_state/2,
  os_state/2,
  forget/1,
  forget/2,
  forget/3,

  get_nodes_stat/1,
  get_node_stat/1,
  get_worker_avg_stat/1,
  get_workers/1
]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).
-define(STAT_LENGTH, 100).

-record(state, {
  nodes = #{},
  workers = #{},
  avg_workers = #{}
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



%%--------------------------------------------------------------------
%% @doc
%% Notification about worker state
%%
%% @end
%%--------------------------------------------------------------------
worker_state(Node, WorkerState) when is_atom(Node), is_record(WorkerState, worker_state) ->
  gen_server:cast(?SERVER, {worker_state, {Node, WorkerState}}).


%%--------------------------------------------------------------------
%% @doc
%% Notification about OS state
%%
%% @end
%%--------------------------------------------------------------------
os_state(Node, OsState) when is_atom(Node), is_record(OsState, os_state) ->
  gen_server:cast(?SERVER, {os_state, {Node, OsState}}).


%%--------------------------------------------------------------------
%% @doc
%% Remove worker statistics
%%
%% @end
%%--------------------------------------------------------------------
forget(Node) ->
  gen_server:cast(?SERVER, {forget, {Node}}).

forget(Node, Worker) ->
  gen_server:cast(?SERVER, {forget, {Node, Worker}}).

forget(Node, Worker, Pid) ->
  gen_server:cast(?SERVER, {forget, {Node, Worker, Pid}}).


%%--------------------------------------------------------------------
%% @doc
%% Return nodes load statistics
%%
%% @end
%%--------------------------------------------------------------------
get_nodes_stat(Nodes) when is_list(Nodes) ->
  gen_server:call(?SERVER, {get_nodes_stat, Nodes}).

get_node_stat(Node) when is_atom(Node) ->
  gen_server:call(?SERVER, {get_node_stat, Node}).


%%--------------------------------------------------------------------
%% @doc
%% Return worker avg load statistics
%%
%% @end
%%--------------------------------------------------------------------
get_worker_avg_stat(Worker) when is_atom(Worker) ->
  gen_server:call(?SERVER, {get_worker_avg_stat, Worker}).

get_workers(Node)->
  gen_server:call(?SERVER, {get_workers, Node}).


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
  {ok, #state{}}.

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

handle_call({get_nodes_stat, Nodes}, _From, State) ->
  Result = maps:filter(fun(Node, _NodeStat) ->
                          lists:member(Node, Nodes)
                        end, State#state.nodes),
  {reply, Result, State};


handle_call({get_node_stat, Node}, _From, State) ->
  Result = nested:get([Node], State#state.nodes, #os_state{}),
  {reply, Result, State};


handle_call({get_worker_avg_stat, Worker}, _From, State) ->
  Result = nested:get([Worker], State#state.avg_workers, #avg_worker{}),
  {reply, Result, State};


handle_call({get_workers, Node}, _From, State) ->
  Result = nested:get([Node], State#state.workers, []),
  {reply, Result, State};

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

%% information about worker state
handle_cast({worker_state, {Node, WorkerState}}, State) ->
  %?DBG("Recieve worker state ~p on node ~p", [WorkerState, Node]),

  Workers = nested:put([Node, WorkerState#worker_state.name, WorkerState#worker_state.pid], WorkerState, State#state.workers),
  WorkerStat = nested:get([WorkerState#worker_state.name], State#state.avg_workers, #avg_worker{}),

  CpuStat = if
              length(WorkerStat#avg_worker.cpu) > ?STAT_LENGTH ->
                lists:nthtail(length(WorkerStat#avg_worker.cpu) - ?STAT_LENGTH, WorkerStat#avg_worker.cpu);
              true -> WorkerStat#avg_worker.cpu
            end ++ [WorkerState#worker_state.cpu],
  AvgCpu = percentile(CpuStat, 0.9),

  MemStat = if
              length(WorkerStat#avg_worker.mem) > ?STAT_LENGTH ->
                lists:nthtail(length(WorkerStat#avg_worker.mem) - ?STAT_LENGTH, WorkerStat#avg_worker.mem);
              true -> WorkerStat#avg_worker.mem
            end ++ [WorkerState#worker_state.memory],
  AvgMem = percentile(MemStat, 0.9),

  AvgWorkersStat = nested:put(
    [WorkerState#worker_state.name],
    WorkerStat#avg_worker{cpu = CpuStat, avg_cpu = AvgCpu, mem = MemStat, avg_mem = AvgMem},
    State#state.avg_workers),

  %?DBG("Workers Stat ~p", [Workers]),
  %?DBG("Avg Stat ~p", [AvgWorkersStat]),

  {noreply, State#state{workers = Workers, avg_workers = AvgWorkersStat}};


%% information about node OS state
handle_cast({os_state, {Node, OsState}}, State) ->
  Nodes = nested:put([Node], OsState, State#state.nodes),

  %?DBG("Nodes stat ~p", [Nodes]),
  {noreply, State#state{nodes = Nodes}};


%% remove statistics
handle_cast({forget, {Node}}, State) ->
  Nodes = nested:remove([Node], State#state.nodes),
  Workers = nested:remove([Node], State#state.workers),
  {noreply, State#state{nodes = Nodes, workers = Workers}};

handle_cast({forget, {Node, Worker}}, State) ->
  Workers = nested:remove([Node, Worker], State#state.workers),
  {noreply, State#state{workers = Workers}};

handle_cast({forget, {Node, Worker, Pid}}, State) ->
  Workers = nested:remove([Node, Worker, Pid], State#state.workers),
  {noreply, State#state{workers = Workers}};


%% handle any request
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

%%
%% @doc erlang module to calculate percentile
%%
%% @author Rodolphe Quiedeville <rodolphe@quiedeville.org>
%%   [http://rodolphe.quiedeville.org]
%%
%% @copyright 2013 Rodolphe Quiedeville
%% @end
percentile(L, P)->
  K = (length(L) - 1) * P,
  F = floor(K),
  C = ceiling(K),
  final(lists:sort(L),F,C,K).

final(L,F,C,K) when (F == C)->
  lists:nth(trunc(K) + 1,L);
final(L,F,C,K) ->
  pos(L,F,C,K) + pos(L,C,K,F).

pos(L,A,B,C)->
  lists:nth(trunc(A) + 1,L) * (B - C).

%% @doc http://schemecookbook.org/Erlang/NumberRounding
floor(X) ->
  T = erlang:trunc(X),
  case (X - T) of
    Neg when Neg < 0 -> T - 1;
    Pos when Pos > 0 -> T;
    _ -> T
  end.

%% @doc http://schemecookbook.org/Erlang/NumberRounding
ceiling(X) ->
  T = erlang:trunc(X),
  case (X - T) of
    Neg when Neg < 0 ->
      T;
    Pos when Pos > 0 -> T + 1;
    _ -> T
  end.

