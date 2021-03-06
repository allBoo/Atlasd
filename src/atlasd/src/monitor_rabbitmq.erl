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
-include_lib("rabbitmq_monitor.hrl").

%% API
-export([
  start_link/1,
  mode/0,
  children_specs/1,
  decode_config/1
]).

%% gen_fsm callbacks
-export([init/1,
  get_data/2,
  process/2,
  handle_event/3,
  handle_sync_event/4,
  handle_info/3,
  terminate/3,
  code_change/4]).

-define(SERVER, ?MODULE).

-record(state, {
  task, rake,
  monitor           :: #rabbitmq_monitor{},
  queues = []         :: list(),
  workers_count = 0 :: integer()
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
children_specs([]) -> [];
children_specs([Config | Tail]) ->
  [child_spec(Config) | children_specs(Tail)].

child_spec(Config) when is_record(Config, rabbitmq_monitor), Config#rabbitmq_monitor.process_per_task == true ->
  lists:map(
    fun(Task) ->
      Name = list_to_atom("monitor_rabbitmq_" ++ atom_to_list(Task#rabbitmq_monitor_task.task)),
      MonitorConfig = Config#rabbitmq_monitor{tasks = [Task]},
      ?CHILD(Name, ?MODULE, [MonitorConfig])
    end, Config#rabbitmq_monitor.tasks);

child_spec(Config) when is_record(Config, rabbitmq_monitor) ->
  Name = list_to_atom("monitor_rabbitmq_" ++ Config#rabbitmq_monitor.host),
  ?CHILD(Name, ?MODULE, [Config]);

child_spec(_) -> [].


%% decode monitor config from json
decode_config([]) -> [];
decode_config([RawConfig | Tail]) ->
  [map_to_record(RawConfig, rabbitmq_monitor) | decode_config(Tail)].

map_to_record(Record, rabbitmq_monitor) ->
  #rabbitmq_monitor{
    mode = binary_to_atom(maps:get(<<"mode">>, Record, <<"api">>), utf8),
    host = binary_to_list(maps:get(<<"host">>, Record)),
    port = binary_to_list(maps:get(<<"port">>, Record, <<"15672">>)),
    user = binary_to_list(maps:get(<<"user">>, Record, <<"guest">>)),
    pass = binary_to_list(maps:get(<<"pass">>, Record, <<"guest">>)),
    vhost = binary_to_list(maps:get(<<"vhost">>, Record, <<"%2f">>)),
    exchange = binary_to_list(maps:get(<<"exchange">>, Record, <<"test">>)),
    process_per_task = util:format_boolean(maps:get(<<"process_per_task">>, Record, false)),
    tasks = lists:map(fun(Task) -> map_to_record(Task, rabbitmq_monitor_task) end, maps:get(<<"tasks">>, Record, []))
  };

map_to_record(Record, rabbitmq_monitor_task) ->
  #rabbitmq_monitor_task{
    task = binary_to_atom(maps:get(<<"task">>, Record), utf8),
    queue = binary_to_list(maps:get(<<"queue">>, Record)),
    rake = util:format_integer(maps:get(<<"rake">>, Record, 10))
  }.

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
  {ok, get_data, #state{monitor = Config}, 1}.

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
-spec(get_data(Event :: term(), State :: #state{}) ->
  {next_state, NextStateName :: atom(), NextState :: #state{}} |
  {next_state, NextStateName :: atom(), NextState :: #state{},
    timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).

get_data(_Event, #state{monitor = Monitor} = State) when Monitor#rabbitmq_monitor.mode == api,
                                                         Monitor#rabbitmq_monitor.process_per_task == true ->
  [Task | _] = Monitor#rabbitmq_monitor.tasks,
  Data = rabbitmq_api:get_queue_by_name(Monitor, Task#rabbitmq_monitor_task.queue),
  {next_state, process, State#state{queues = Data}, 1};

get_data(_Event, #state{monitor = Monitor} = State) when Monitor#rabbitmq_monitor.mode == api ->
  Data = rabbitmq_api:get_all_queues(Monitor),
  {next_state, process, State#state{queues = Data}, 1};

get_data(_Event, #state{monitor = Monitor} = State) when Monitor#rabbitmq_monitor.mode == native ->
  ?WARN(?ERROR_UNCOMPLETED),
  Data = [],
  {next_state, process, State#state{queues = Data}, 1}.

process(_Event, #state{monitor = Monitor} = State) ->
  Workers = get_workers_count(Monitor#rabbitmq_monitor.tasks),
  process_tasks(Monitor#rabbitmq_monitor.tasks, State#state.queues, Workers),
  {next_state, get_data, State#state{workers_count = Workers}, 10000}.


get_workers_count(Tasks) -> get_workers_count(Tasks, maps:new()).
get_workers_count([], Result) -> Result;
get_workers_count([Task | Tail], Result) ->
  Count = length(master:get_worker_instances(Task#rabbitmq_monitor_task.task)),
  get_workers_count(Tail, maps:put(Task#rabbitmq_monitor_task.task, Count, Result)).

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
  {next_state, StateName, State, 10000}.

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

handle_sync_event(get_data, _From, StateName, State) ->
  {reply, {State#state.queues, State#state.workers_count}, StateName, State, 10000};

handle_sync_event(_Event, _From, StateName, State) ->
  {reply, ok, StateName, State, 10000}.

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
  {next_state, StateName, State, 10000}.

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

process_tasks([], _, _) -> ok;
process_tasks([Task | Tasks], Queues, Workers) ->
  Queue = maps:get(Task#rabbitmq_monitor_task.queue, Queues, #rabbitmq_queue{}),
  ConsumersCount = maps:get(Task#rabbitmq_monitor_task.task, Workers, 0),

%%  ?DBG("There are ~p messages in queue ~p and ~p consumers for task ~p", [
%%    Queue#rabbitmq_queue.messages, Queue#rabbitmq_queue.name, ConsumersCount, Task#rabbitmq_monitor_task.task
%%    ]),

  Estimated_time =
    if
      Queue#rabbitmq_queue.ack_rate == 0.0 -> -1;
      true -> round((Queue#rabbitmq_queue.messages / Queue#rabbitmq_queue.ack_rate) / 60)
    end,

  if
    Queue#rabbitmq_queue.messages =:= 0, ConsumersCount =/= 0, Queue#rabbitmq_queue.publish_rate =:= 0.0 ->
      atlasd:change_workers_count(Task#rabbitmq_monitor_task.task, 0);

    Queue#rabbitmq_queue.messages =:= 0, ConsumersCount > 1, Queue#rabbitmq_queue.publish_rate =/= 0.0 ->
      atlasd:decrease_workers(Task#rabbitmq_monitor_task.task);
    true -> ok
  end,

  if
    Queue#rabbitmq_queue.messages =/= 0, ConsumersCount =:= 0 ->
      atlasd:change_workers_count(Task#rabbitmq_monitor_task.task, 1);
    true -> ok
  end,

  if
    Queue#rabbitmq_queue.messages =/= 0, ConsumersCount =/= 0, Queue#rabbitmq_queue.messages < ConsumersCount ->
      atlasd:change_workers_count(Task#rabbitmq_monitor_task.task, Queue#rabbitmq_queue.messages);
    true -> ok
  end,

  if
    Queue#rabbitmq_queue.messages =/= 0, ConsumersCount =/= 0, Queue#rabbitmq_queue.messages > ConsumersCount ->
      if
        Estimated_time > Task#rabbitmq_monitor_task.rake ->
          atlasd:increase_workers(Task#rabbitmq_monitor_task.task);

        Estimated_time =:= -1, ConsumersCount < 100 ->
          atlasd:increase_workers(Task#rabbitmq_monitor_task.task);

        true -> ok
      end;

    true -> ok
  end,

  process_tasks(Tasks, Queues, Workers).


