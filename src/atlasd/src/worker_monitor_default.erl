%%%-------------------------------------------------------------------
%%% @author alboo
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 30. апр 2015 0:44
%%%-------------------------------------------------------------------
-module(worker_monitor_default).
-author("alboo").

-behaviour(gen_fsm).
-include_lib("atlasd.hrl").

%% API
-export([start_link/3]).

%% gen_fsm callbacks
-export([init/1,
  wait/2,
  monitor/2,
  handle_event/3,
  handle_sync_event/4,
  handle_info/3,
  terminate/3,
  code_change/4]).

-define(SERVER, ?MODULE).

-record(state, {
  sup_pid = undefined :: pid(),
  worker_pid = undefined :: pid(),
  worker_ref = undefined :: reference(),
  worker_proc = undefined :: integer(),
  worker = undefined :: #worker{},
  time = erlang:timestamp()
}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Creates a gen_fsm process which calls Module:init/1 to
%% initialize. To ensure a synchronized start-up procedure, this
%% function does not return until Module:init/1 has returned.
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link(SupPid :: pid(), WorkerPid :: pid(), Worker :: #worker{}) ->
  {ok, pid()} | ignore | {error, Reason :: term()}).
start_link(SupPid, WorkerPid, Worker) when is_pid(SupPid), is_pid(WorkerPid), is_record(Worker, worker) ->
  gen_fsm:start_link(?MODULE, [SupPid, WorkerPid, Worker], []).

%%%===================================================================
%%% gen_fsm callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_fsm is started using gen_fsm:start/[3,4] or
%% gen_fsm:start_link/[3,4], this function is called by the new
%% process to initialize.
%%
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
  {ok, StateName :: atom(), StateData :: #state{}} |
  {ok, StateName :: atom(), StateData :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([SupPid, WorkerPid, Worker]) ->
  ?DBG("Worker default monitor started ~p", [Worker#worker.name]),
  WorkerProc = worker:get_proc_pid(WorkerPid),
  State = if
            is_integer(WorkerProc) -> monitor;
            true -> wait
          end,

  Monitor = erlang:monitor(process, WorkerPid),

  {ok, State, #state{
    sup_pid = SupPid,
    worker_pid = WorkerPid,
    worker_ref = Monitor,
    worker_proc = WorkerProc,
    worker = Worker,
    time = erlang:timestamp()
  }, 1000}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% There should be one instance of this function for each possible
%% state name. Whenever a gen_fsm receives an event sent using
%% gen_fsm:send_event/2, the instance of this function with the same
%% name as the current state name StateName is called to handle
%% the event. It is also called if a timeout occurs.
%%
%% @end
%%--------------------------------------------------------------------
-spec(wait(Event :: term(), State :: #state{}) ->
  {next_state, NextStateName :: atom(), NextState :: #state{}} |
  {next_state, NextStateName :: atom(), NextState :: #state{},
    timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).

wait(_Event, State) ->
  WorkerProc = worker:get_proc_pid(State#state.worker_pid),
  NextState = if
                is_integer(WorkerProc) -> monitor;
                true -> wait
              end,

  {next_state, NextState, State#state{worker_proc = WorkerProc}, 1000}.

%%
monitor(_Event, State) ->
  WorkerState = #worker_state{
    name = (State#state.worker)#worker.name,
    pid = State#state.worker_pid,
    proc = State#state.worker_proc,
    memory = get_mem_usage(State#state.worker_proc),
    cpu = get_cpu_usage(State#state.worker_proc),
    uptime = timer:now_diff(erlang:timestamp(), State#state.time)
  },
  atlasd:notify_state(worker_state, WorkerState),

  case check_memory_usage(WorkerState#worker_state.memory, State) of
    false ->
      ?LOG("Memory consumption too large on worker ~p", [(State#state.worker)#worker.name]),
      atlasd:restart_worker(State#state.worker_pid),
      ok;
    true -> ok
  end,
  {next_state, monitor, State, 1000}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_fsm receives an event sent using
%% gen_fsm:send_all_state_event/2, this function is called to handle
%% the event.
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_event(Event :: term(), StateName :: atom(),
    StateData :: #state{}) ->
  {next_state, NextStateName :: atom(), NewStateData :: #state{}} |
  {next_state, NextStateName :: atom(), NewStateData :: #state{},
    timeout() | hibernate} |
  {stop, Reason :: term(), NewStateData :: #state{}}).
handle_event(_Event, StateName, State) ->
  {next_state, StateName, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_fsm receives an event sent using
%% gen_fsm:sync_send_all_state_event/[2,3], this function is called
%% to handle the event.
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_sync_event(Event :: term(), From :: {pid(), Tag :: term()},
    StateName :: atom(), StateData :: term()) ->
  {reply, Reply :: term(), NextStateName :: atom(), NewStateData :: term()} |
  {reply, Reply :: term(), NextStateName :: atom(), NewStateData :: term(),
    timeout() | hibernate} |
  {next_state, NextStateName :: atom(), NewStateData :: term()} |
  {next_state, NextStateName :: atom(), NewStateData :: term(),
    timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewStateData :: term()} |
  {stop, Reason :: term(), NewStateData :: term()}).
handle_sync_event(_Event, _From, StateName, State) ->
  Reply = ok,
  {reply, Reply, StateName, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_fsm when it receives any
%% message other than a synchronous or asynchronous event
%% (or a system message).
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: term(), StateName :: atom(),
    StateData :: term()) ->
  {next_state, NextStateName :: atom(), NewStateData :: term()} |
  {next_state, NextStateName :: atom(), NewStateData :: term(),
    timeout() | hibernate} |
  {stop, Reason :: normal | term(), NewStateData :: term()}).


%% worker stoped
handle_info({'DOWN', MonitorRef, _, _WorkerPid, _}, _, State) when MonitorRef == State#state.worker_ref ->
  ?DBG("Shutdown worker ~p supervisor ~p", [(State#state.worker)#worker.name, State#state.sup_pid]),
  exit(State#state.sup_pid, kill),
  {stop, shutdown, State};


handle_info(_Info, StateName, State) ->
  {next_state, StateName, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_fsm when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_fsm terminates with
%% Reason. The return value is ignored.
%%
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: normal | shutdown | {shutdown, term()}
| term(), StateName :: atom(), StateData :: term()) -> term()).
terminate(_Reason, _StateName, _State) ->
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, StateName :: atom(),
    StateData :: #state{}, Extra :: term()) ->
  {ok, NextStateName :: atom(), NewStateData :: #state{}}).
code_change(_OldVsn, StateName, State, _Extra) ->
  {ok, StateName, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

check_memory_usage(Memory, State) when (State#state.worker)#worker.max_mem =/= infinity ->
  Worker = State#state.worker,
  MaxMem = case Worker#worker.max_mem of
             {k, Value} -> Value * 1024;
             {m, Value} -> Value * 1024 * 1024;
             {g, Value} -> Value * 1024 * 1024 * 1024;
             _ -> infinity
           end,
  %?DBG("Memory consumption of worker ~p is ~p", [Worker#worker.name, Memory]),
  Memory < MaxMem;

check_memory_usage(_Memory, _State) ->
  true.


%% calc process memory usage
%% TODO this is only for linux
get_mem_usage(ProcPid) ->
  FileName = "/proc/" ++ integer_to_list(ProcPid) ++ "/status",
  {ok, Device} = file:open(FileName, [read]),
  try calc_mem_lines(Device)
    after file:close(Device)
  end.

calc_mem_lines(Device) ->
  case io:get_line(Device, "") of
    eof  -> 0;
    Line ->
      case string:tokens(Line, " \t\n") of
        [Part, Mem, "kB"] when (Part == "VmRSS:") or (Part == "VmSwap:") ->
          list_to_integer(Mem) * 1024;
        _ -> 0
      end
        + calc_mem_lines(Device)
  end.


%% calc process CPU usage
get_cpu_usage(ProcPid) ->
  try
    Result = os:cmd(io_lib:format("ps -p ~B -o %cpu", [ProcPid])),
    case io_lib:fread("%CPU\n~f\n", Result) of
      {ok, [Percents], []} -> Percents;
      _ ->
        case io_lib:fread("%CPU\n~d\n", Result) of
          {ok, [Percents], []} -> Percents + 0.0;
          _ -> 0.0
        end
    end
  catch
     _:_ -> 0.0
  end.
