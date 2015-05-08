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
  worker_started/1,
  worker_stoped/1,
  start_worker/1,
  stop_worker/1
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


is_worker() ->
  config:get("node.worker", false, boolean).

%% start worker
start_worker(Worker) ->
  gen_server:cast(?SERVER, {start_worker, Worker}).

%% stop worker
stop_worker(WorkerPid) when is_pid(WorkerPid) ->
  gen_server:cast(?SERVER, {stop_worker, WorkerPid}).

%% workers must use this function to inform master about itself
worker_started({Pid, Name} = Worker) when is_pid(Pid), is_atom(Name) ->
  gen_server:cast(?SERVER, {worker_started, Worker}).

worker_stoped({Pid, Name} = Worker) when is_pid(Pid), is_atom(Name) ->
  gen_server:cast(?SERVER, {worker_stoped, Worker}).

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


handle_call(is_worker, _From, State) ->
  {reply, is_worker(), State};


handle_call(get_workers, _From, State) ->
  case is_worker() of
    true -> {reply, workers_sup:get_workers(), State};
    _ -> {reply, ignore, State}
  end;


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
  ?DBG("Try to start worker ~p", [Worker]),
  do_start_worker(Worker),
  {noreply, State};

%% stop worker
handle_cast({stop_worker, WorkerPid}, State) when is_pid(WorkerPid) ->
  ?DBG("Try to gracefully stop worker ~p", [WorkerPid]),
  do_stop_worker(WorkerPid),
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