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
  get_config/1,
  get_log/2,
  log_enable/1,
  log_disable/1,
  set_log_handler/3,
  remove_log_handler/2
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
  incomplete = <<>>,
  log = [],
  log_enabled = true,
  log_size = 10,
  log_handlers = []
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

log_enable(WorkerRef) when is_pid(WorkerRef) ->
  gen_server:call(WorkerRef, log_enable).

log_disable(WorkerRef) when is_pid(WorkerRef) ->
  gen_server:call(WorkerRef, log_disable).


get_log(WorkerRef, LineId) when is_pid(WorkerRef) ->
  gen_server:call(WorkerRef, {get_log, LineId}).

set_log_handler(WorkerRef, Handler, Name) when is_pid(WorkerRef) ->
  gen_server:call(WorkerRef, {set_log_handler, Handler, Name}).

remove_log_handler(WorkerRef, Name) when is_pid(WorkerRef) ->
  gen_server:call(WorkerRef, {remove_log_handler, Name}).
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

handle_call({get_log, LastLineId}, _From, State) ->
  Log = [{LogLineId, LogLine} || {LogLineId, LogLine} <- State#state.log, LogLineId > LastLineId],
  {reply, Log, State};

handle_call(log_enable, _From, State) ->
  {noreply, State#state{log_enabled = true}};

handle_call(log_disable, _From, State) ->
  {noreply, State#state{log_enabled = false}};

handle_call({set_log_handler, Handler, Name}, _From, State) ->
  Exists = [{N, H} || {N, H} <- State#state.log_handlers, N == Name],

  LogHandlers = if
    Exists /= [] ->
      State#state.log_handlers;
    true ->
      lists:append(State#state.log_handlers, [{Name, Handler}])
  end,

  {reply, ok, State#state{log_handlers = LogHandlers}};

handle_call({remove_log_handler, Name}, _From, State) ->
  {noreply, State#state{log_handlers = [{N, H} || {N, H} <- State#state.log_handlers, N /= Name]}};

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

handle_info({Port, {data, {eol, Data}}}, State) when Port == State#state.port, State#state.log_enabled =:= true ->
  CurrentLog = State#state.incomplete,
  LogLine = <<CurrentLog/binary, Data/binary>>,

  lists:foreach(
    fun({_Name, Handler}) ->
      Handler(LogLine)
    end,
    State#state.log_handlers),

  NewLineId = case length(State#state.log) > 0 of
    true -> {LineId, _} = lists:last(State#state.log), LineId+1;
    _ -> 0
  end,
  CompleteLog = {NewLineId, LogLine},

  AllLines = lists:append(State#state.log, [CompleteLog]),
  Log = if
    length(AllLines) > State#state.log_size ->
      lists:sublist(AllLines, 1 + (length(AllLines) - State#state.log_size), State#state.log_size + 1);
    true ->
      AllLines
  end,

  %?DBG("complete log ~p", [Log]),
  %?DBG("complete stdout ~p", [CompleteLog]),
  {noreply, State#state{incomplete = <<>>, last_line = CompleteLog, log = Log }};

handle_info({Port, {data, {noeol, Data}}}, State) when Port == State#state.port, State#state.log_enabled =:= true ->
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

