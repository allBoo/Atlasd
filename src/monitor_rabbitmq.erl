%%%-------------------------------------------------------------------
%%% @author alboo
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 04. июн 2015 1:30
%%%-------------------------------------------------------------------
-module(monitor_rabbitmq).
-author("alboo").

-behaviour(gen_fsm).
-include_lib("atlasd.hrl").

%% API
-export([
  start_link/1,
  mode/0,
  child_specs/1
]).

%% gen_fsm callbacks
-export([init/1,
  state_name/2,
  state_name/3,
  handle_event/3,
  handle_sync_event/4,
  handle_info/3,
  terminate/3,
  code_change/4]).

-define(SERVER, ?MODULE).

-record(state, {
  mode = api :: api | native,
  host = "127.0.0.1",
  port = "15672",
  user = "guest",
  pass = "guest",
  vhost = "/",
  exchange,
  queue,
  task
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
-spec(start_link(Config :: []) -> {ok, pid()} | ignore | {error, Reason :: term()}).
start_link(Config) ->
  gen_fsm:start_link(?MODULE, [Config], []).


%% @static
%% return monitor type
mode() -> master.


%% generates children specs for the supervisor
child_specs(Config) ->
  ParsedState = parse_state(Config, #state{}),
  lists:map(fun(Monitor) ->
    ChildName = list_to_atom("monitor_" ++ Monitor#state.task),
    {ChildName, {?MODULE, start_link, [Monitor]}, permanent, 5000, worker, [?MODULE]}
  end, parse_monitors(Config, ParsedState, [])).

parse_state([], State) -> State;
parse_state([{"mode", Value} | Config], State) ->
  parse_state(Config, State#state{mode = list_to_atom(Value)});
parse_state([{"host", Value} | Config], State) ->
  parse_state(Config, State#state{host = Value});
parse_state([{"port", Value} | Config], State) ->
  parse_state(Config, State#state{port = Value});
parse_state([{"user", Value} | Config], State) ->
  parse_state(Config, State#state{user = Value});
parse_state([{"pass", Value} | Config], State) ->
  parse_state(Config, State#state{pass = Value});
parse_state([{"vhost", Value} | Config], State) ->
  parse_state(Config, State#state{vhost = Value});
parse_state([{"exchange", Value} | Config], State) ->
  parse_state(Config, State#state{exchange = Value});
parse_state([{"queue", Value} | Config], State) ->
  parse_state(Config, State#state{queue = Value});
parse_state([{"task", Value} | Config], State) ->
  parse_state(Config, State#state{task = Value});
parse_state([_ | Config], State) ->
  parse_state(Config, State).

parse_monitors([], _State, Monitors) -> Monitors;
parse_monitors([{"monitors", Value} | Config], State, _Monitors) ->
  parse_monitors(Config, State, parse_monitor(Value, State, []));
parse_monitors([_ | Config], State, Monitors) ->
  parse_monitors(Config, State, Monitors).

parse_monitor([], _State, Monitors) -> Monitors;
parse_monitor([{TaskName, MonitorConfig} | Config], State, Monitors) ->
  parse_monitor(Config, State, [parse_state(MonitorConfig, State#state{task = TaskName}) | Monitors]);
parse_monitor([_ | Config], State, Monitors) ->
  parse_monitor(Config, State, Monitors).

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
init([Config]) ->
  ?DBG("Started rabbitmq monitor ~p", [Config]),
  {ok, state_name, #state{}}.

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
-spec(state_name(Event :: term(), State :: #state{}) ->
  {next_state, NextStateName :: atom(), NextState :: #state{}} |
  {next_state, NextStateName :: atom(), NextState :: #state{},
    timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
state_name(_Event, State) ->
  {next_state, state_name, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% There should be one instance of this function for each possible
%% state name. Whenever a gen_fsm receives an event sent using
%% gen_fsm:sync_send_event/[2,3], the instance of this function with
%% the same name as the current state name StateName is called to
%% handle the event.
%%
%% @end
%%--------------------------------------------------------------------
-spec(state_name(Event :: term(), From :: {pid(), term()},
    State :: #state{}) ->
  {next_state, NextStateName :: atom(), NextState :: #state{}} |
  {next_state, NextStateName :: atom(), NextState :: #state{},
    timeout() | hibernate} |
  {reply, Reply, NextStateName :: atom(), NextState :: #state{}} |
  {reply, Reply, NextStateName :: atom(), NextState :: #state{},
    timeout() | hibernate} |
  {stop, Reason :: normal | term(), NewState :: #state{}} |
  {stop, Reason :: normal | term(), Reply :: term(),
    NewState :: #state{}}).
state_name(_Event, _From, State) ->
  Reply = ok,
  {reply, Reply, state_name, State}.

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
