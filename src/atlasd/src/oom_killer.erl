%%%-------------------------------------------------------------------
%%% @author user
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 18. Дек. 2015 11:24
%%%-------------------------------------------------------------------
-module(oom_killer).
-author("user").

-behaviour(gen_fsm).
-include_lib("atlasd.hrl").

%% API
-export([start_link/1]).

%% gen_fsm callbacks
-export([init/1,
  kill/2,
  wait/2,
  iddle/2,
  handle_event/3,
  handle_sync_event/4,
  handle_info/3,
  terminate/3,
  code_change/4]).

-define(SERVER, ?MODULE).

-record(state, {
  fat_worker_pid = 0
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
-spec(start_link(Args :: term()) -> {ok, pid()} | ignore | {error, Reason :: term()}).
start_link(Node) ->
  gen_fsm:start_link(?MODULE, [Node], []).

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
init([Node]) ->
  ?DBG("Started oom killer"),
  reg:name({oom_killer, Node}),
  {ok, kill, #state{}, 1000}.

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
-spec(kill(Event :: term(), State :: #state{}) ->
  {next_state, NextStateName :: atom(), NextState :: #state{}} |
  {next_state, NextStateName :: atom(), NextState :: #state{},
    timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).

kill(_Event, State)->
  {next_state, wait, State#state{fat_worker_pid = kill_fat_worker()}, 1000}.

wait(Event, State) when Event /= kill ->
  case is_pid(State#state.fat_worker_pid) of
    true ->
      case process_info(State#state.fat_worker_pid) of
        undefined ->
          {next_state, iddle, State};
        _ ->
          {next_state, wait, State, 5000}
      end;
    _ -> {next_state, iddle, State}
end;

wait(_Event, State) ->
  {next_state, wait, State}.

%%
iddle(Event, State) when Event == kill ->
  {next_state, kill, State, 1000};

iddle(_Event, State) ->
  {next_state, iddle, State}.




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


kill_fat_worker() ->
  Workers = statistics:get_workers(node()),
  if
    Workers /= [] ->
      TaskNames = [X || X <- nested:keys([], Workers),
        (config:worker(X))#worker.restart /= disallow],

      WorkersStates = lists:flatten(
        [
          X || X <- [
          W || W <- get_workers_states(TaskNames, Workers), W /= []
        ],
          ((((config:worker((lists:last(X))#worker_state.name))#worker.procs)#worker_procs.each_node /= 1)
            or (length(X) > 1))
        ]),

      ?DBG("Workers count that can be killed ~w", [length(WorkersStates)]),
      case get_fat_worker(WorkersStates) of
        {ok, FatWorker} ->
          cluster:notify(node(), {stop_worker, FatWorker#worker_state.pid}),
          FatWorker#worker_state.pid;
        _ -> false
      end;
    true -> false
  end.


get_fat_worker([]   ) -> empty;
get_fat_worker([H|T]) -> {ok, get_fat_worker(H, T)}.

get_fat_worker(X, []   )            -> X;
get_fat_worker(X, [H|T]) when (X#worker_state.cpu+X#worker_state.memory) < (H#worker_state.cpu+H#worker_state.memory) -> get_fat_worker(H, T);
get_fat_worker(X, [_|T])            -> get_fat_worker(X, T).



get_workers_states([H|T], L) ->
  W = nested:get([H], L, []),
  if is_record(W, worker_state) ->
    [ W | get_workers_states(T, L) ];
    true -> [get_workers_states(nested:keys([], W), W) | get_workers_states(T, L) ]
  end;

get_workers_states([], _) ->
  [].