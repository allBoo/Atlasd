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
  child_specs/1,
  process_queue/2
]).

%% gen_fsm callbacks
-export([init/1,
  monitor/2,
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
  vhost = "%2f",
  minutes_to_add_consumers = 1000,
  exchange,
  queue,
  task
}).


-record(queue, {name,
  messages,
  consumers,
  publish_rate,
  ack_rate}).

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
  lists:map(fun(Task) ->
                  {list_to_atom("monitor_" ++ Task#rabbitmq_monitor_task.task), {?MODULE, start_link, [
                    #state{
                      mode = Config#rabbitmq_monitor.mode,
                      host = Config#rabbitmq_monitor.host,
                      port = Config#rabbitmq_monitor.port,
                      user = Config#rabbitmq_monitor.user,
                      pass = Config#rabbitmq_monitor.pass,
                      vhost = Task#rabbitmq_monitor_task.vhost,
                      minutes_to_add_consumers = Task#rabbitmq_monitor_task.minutes_to_add_consumers,
                      exchange = Task#rabbitmq_monitor_task.exchange,
                      queue = Task#rabbitmq_monitor_task.queue,
                      task = Task#rabbitmq_monitor_task.task
                    }
                  ]}, permanent, 5000, worker, [?MODULE]}
                end,
    Config#rabbitmq_monitor.tasks).

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
  ?DBG("Started rabbitmq monitor for worker ~p", [Config#state.task]),
  {ok, monitor, Config, 10000}.

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
-spec(monitor(Event :: term(), State :: #state{}) ->
  {next_state, NextStateName :: atom(), NextState :: #state{}} |
  {next_state, NextStateName :: atom(), NextState :: #state{},
    timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).

monitor(_Event, State) ->
  process_queue(rabbitmq_api:get_queue_by_name(State), State),
  {next_state, monitor, State, 10000}.

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

process_queue(Queue, State) when Queue /= false ->
  %?DBG("Processing queue: ~p~n", [Queue#queue.name]),
  Estimated_time =
    if
      Queue#queue.ack_rate == 0.0 -> -1;
      true -> round((Queue#queue.messages / Queue#queue.ack_rate) / 60)
    end,

  if
    Queue#queue.messages =:= 0, Queue#queue.consumers =/= 0, Queue#queue.publish_rate =:= 0.0 ->
%%      ?DBG("~w messages, ~w consumers, consumers must be killed ~n", [
%%        Queue#queue.messages,
%%        Queue#queue.consumers
%%      ]),
      atlasd:change_workers_count(State#state.task, 0);

    Queue#queue.messages =:= 0, Queue#queue.consumers > 1, Queue#queue.publish_rate =/= 0.0 ->
%%      ?DBG("~w messages, ~w consumers, publish rate ~w, consumers must be decreased ~n", [
%%        Queue#queue.messages,
%%        Queue#queue.consumers,
%%        Queue#queue.publish_rate
%%      ]),
      atlasd:decrease_workers(State#state.task);
    true -> ok
  end,

  if
    Queue#queue.messages =/= 0, Queue#queue.consumers =:= 0 ->
%%    ?DBG("~p consumers, ~p messages, consumers must be added ~n", [
%%      Queue#queue.consumers,
%%      Queue#queue.messages
%%    ]),
      atlasd:change_workers_count(State#state.task, 1);
    true -> ok
  end,

  if
    Estimated_time > State#state.minutes_to_add_consumers ->
%%    ?DBG("Estimate time ~p (more than ~p minutes), consumers must be added ~n", [
%%      Estimated_time, State#state.minutes_to_add_consumers
%%    ]),
    atlasd:increase_workers(State#state.task);
    true -> ok
  end,

%%  ?DBG("--------------------------------------------------"),
%%  ?DBG("Publish rate: ~p/s ~n", [Queue#queue.publish_rate]),
%%  ?DBG("Ack rate: ~p/s ~n", [Queue#queue.ack_rate]),
%%  ?DBG("Messages count: ~p ~n", [Queue#queue.messages]),
%%  ?DBG("Consumers count: ~p ~n", [Queue#queue.consumers]),
%%  ?DBG("--------------------------------------------------"),
%%  ?DBG("Estimated time: ~p minutes ~n", [Estimated_time]),
%%  ?DBG("--------------------------------------------------"),
  ok;

process_queue(Queue, State) when Queue == false ->
  ?WARN("Queue proccess failed ~p", [State]),
  failed.

