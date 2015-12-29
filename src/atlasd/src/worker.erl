%%%-------------------------------------------------------------------
%%% @author alboo
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 30. апр 2015 0:39
%%%-------------------------------------------------------------------
-module(worker).
-author("alboo").

-behaviour(gen_server).
-include_lib("atlasd.hrl").

%% API
-export([
  start_link/1,
  get_name/1,
  get_proc_pid/1,
  get_config/1
]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-record(state, {
  config,
  port = undefined,
  pid  = undefined,
  last_line = <<>>,
  incomplete = <<>>
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
-spec(start_link(Worker :: #worker{}) ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Worker) when is_record(Worker, worker) ->
  gen_server:start_link(?MODULE, [Worker], []).


get_name(WorkerRef) when is_pid(WorkerRef) ->
  gen_server:call(WorkerRef, get_name).


get_proc_pid(WorkerRef) when is_pid(WorkerRef) ->
  gen_server:call(WorkerRef, get_proc_pid).


get_config(WorkerRef) when is_pid(WorkerRef) ->
  gen_server:call(WorkerRef, get_config).


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
init([Worker]) when is_record(Worker, worker) ->
  process_flag(trap_exit, true),

  case start_worker(#state{config = Worker}) of
    {ok, State} ->
      atlasd:worker_started({self(), Worker#worker.name}),
      {ok, State};

    {error, Error, _State} ->
      {stop, Error}
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


handle_call(get_name, _From, State) ->
  {reply, (State#state.config)#worker.name, State};

handle_call(get_proc_pid, _From, State) ->
  {reply, State#state.pid, State};

handle_call(get_config, _From, State) ->
  {reply, State#state.config, State};

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

handle_info({Port, {data, {eol, Data}}}, State) when Port == State#state.port ->
  CurrentLog = State#state.incomplete,
  CompleteLog = <<CurrentLog/binary, Data/binary>>,
  ?DBG("complete stdout ~p", [CompleteLog]),
  {noreply, State#state{incomplete = <<>>, last_line = CompleteLog}};


handle_info({Port, {data, {noeol, Data}}}, State) when Port == State#state.port ->
  CurrentLog = State#state.incomplete,
  %?DBG("incomplete stdout ~p", [CurrentLog]),
  {noreply, State#state{incomplete = <<CurrentLog/binary, Data/binary>>}};


%% port is terminated
handle_info({'EXIT', Port, Reason}, State) when is_port(Port), Port == State#state.port ->
  ?DBG("Command is terminated with reason ~p", [Reason]),
  {stop, shutdown, State#state{port = undefined, pid = undefined}};

handle_info({Port, {exit_status, ExitStatus}}, State) when is_port(Port), Port == State#state.port ->
  ?DBG("Command is terminated with exit status ~p", [ExitStatus]),
  {stop, shutdown, State#state{port = undefined, pid = undefined}};


%% terminating self
handle_info({'EXIT', FromPid, Reason}, State) when is_pid(FromPid), is_port(State#state.port) ->
  {noreply, do_terminate_self(Reason, State)};


handle_info(Info, State) ->
  ?DBG("Worker recieve ~p", [Info]),
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

terminate(Reason, State) when is_port(State#state.port) ->
  do_terminate_self(Reason, State),
  ok;

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

start_worker(State) ->
  Worker = State#state.config,
  try
    Port = open_port({spawn, Worker#worker.command}, [stream, binary, exit_status, {line, 1024}]),%%nouse_stdio
    {os_pid, Pid} = erlang:port_info(Port, os_pid),

    ?DBG("Worker ~p started on port ~p with pid ~p", [Worker#worker.name, Port, Pid]),

    {ok, State#state{port = Port, pid = Pid}}
  catch
    _:Error ->
      ?DBG("Error '~p' occured while starting worker", [Error]),
      {error, {worker, Error}, State#state{port = undefined, pid = undefined}}
  end.


stop_worker(State) ->
  Worker = (State#state.config)#worker.name,
  ?DBG("Kill worker ~p [~p]", [Worker, State#state.pid]),

  os:cmd(io_lib:format("kill -9 ~p", [State#state.pid])),
  port_close(State#state.port),
  {ok, State#state{port = undefined, pid = undefined}}.


%% restart_worker(#state{config = Worker} = State) when Worker#worker.restart == disallow ->
%%   {error, disallow, State};
%%
%% restart_worker(#state{config = Worker} = State) when Worker#worker.restart == prestart ->
%%   case start_worker(State) of
%%     {ok, NewState} ->
%%       stop_worker(State),
%%       {ok, NewState};
%%
%%     {error, Error, _} ->
%%       {error, Error, State}
%%   end;
%%
%% restart_worker(State) ->
%%   stop_worker(State),
%%   start_worker(State).


do_terminate_self(Reason, State) ->
  ?DBG("Terminate worker with reason ~p", [Reason]),
  case stop_worker(State) of
    {ok, NewState} ->
      NewState;

    {error, Error, NewState} ->
      ?DBG("Error while terminating worker ~p", [Error]),
      NewState
  end.

