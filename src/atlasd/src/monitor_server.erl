%%%-------------------------------------------------------------------
%%% @author alboo
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 04. июн 2015 1:30
%%%-------------------------------------------------------------------
-module(monitor_server).
-author("alboo").

-behaviour(gen_fsm).
-include_lib("atlasd.hrl").

%% API
-export([
  start_link/1,
  mode/0,
  children_specs/1,
  decode_config/1
]).

%% gen_fsm callbacks
-export([init/1,
  connect/2,
  unlocked/2,
  locked/2,
  handle_event/3,
  handle_sync_event/4,
  handle_info/3,
  terminate/3,
  code_change/4]).

-define(SERVER, ?MODULE).


-record(server_monitor_auth, {
  type :: public_key | password,
  user :: string(),
  password :: string()
}).

-record(server_monitor_watermark, {
  mem = infinity :: infinity | integer(),
  la  = infinity :: infinity | integer()
}).

-record(server_monitor, {
  type       :: atom(),
  host       :: string(),
  port       :: integer(),
  auth       :: #server_monitor_auth{},
  watermark  :: #server_monitor_watermark{},
  tasks = [] :: [atom()],
  nodes = [] :: [atom()]
}).

-record(state, {
  server     :: #server_monitor{},
  connection :: ssh:ssh_connection_ref(),
  la = 0.0   :: float(),
  mem = 0    :: integer()
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
children_specs(Config) ->
  lists:map(fun(Server) ->
                  {list_to_atom("monitor_server_" ++ Server#server_monitor.host), {?MODULE, start_link, [Server]}, permanent, 10000, worker, [?MODULE]}
            end, Config).


%% decode monitor config from json
decode_config([]) -> [];
decode_config([RawConfig | Tail]) ->
  [map_to_record(RawConfig, server_monitor) | decode_config(Tail)].

map_to_record(Record, server_monitor) ->
  #server_monitor{
    type = binary_to_atom(maps:get(<<"type">>, Record), utf8),
    host = binary_to_list(maps:get(<<"host">>, Record)),
    port = util:format_integer(maps:get(<<"port">>, Record, 22)),
    auth = map_to_record(maps:get(<<"auth">>, Record), server_monitor_auth),
    watermark = map_to_record(maps:get(<<"watermark">>, Record), server_monitor_watermark),
    tasks = lists:map(fun(Task) -> binary_to_atom(Task, utf8) end, maps:get(<<"tasks">>, Record, [])),
    nodes = lists:map(fun(Node) -> binary_to_atom(Node, utf8) end, maps:get(<<"nodes">>, Record, []))
  };

map_to_record(Record, server_monitor_auth) ->
  #server_monitor_auth{
    type = binary_to_atom(maps:get(<<"type">>, Record), utf8),
    user = binary_to_list(maps:get(<<"user">>, Record)),
    password = binary_to_list(maps:get(<<"password">>, Record))
  };

map_to_record(Record, server_monitor_watermark) ->
  #server_monitor_watermark{
    la = util:format_inf_integer(maps:get(<<"la">>, Record, infinity)),
    mem = util:format_inf_integer(maps:get(<<"mem">>, Record, infinity))
  };

map_to_record(_, _) -> undefined.

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
init([Server]) when is_record(Server, server_monitor) ->
  ?DBG("Starting server monitor for host ~p", [Server#server_monitor.host]),
  {ok, connect, #state{server = Server}, 1}.

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
-spec(connect(Event :: term(), State :: #state{}) ->
  {next_state, NextStateName :: atom(), NextState :: #state{}} |
  {next_state, NextStateName :: atom(), NextState :: #state{},
    timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).

connect(_Event, State) ->
  Server = State#state.server,
  Options = [
    {silently_accept_hosts, true},
    {user_interaction, false},
    {disconnectfun, fun (Reason) -> disconnect(self(), Server, Reason) end},
    {unexpectedfun, fun (Message, Peer) -> unexpected(Server, Message, Peer) end}
  ] ++ connect_options(Server#server_monitor.auth),

  case ssh:connect(Server#server_monitor.host, Server#server_monitor.port, Options) of
    {ok, Connection} ->
      ?LOG("Server monitor successfully connected to host ~p", [Server#server_monitor.host]),
      {next_state, unlocked, State#state{connection = Connection}, 1};

    {error, Reason} ->
      ?ERR("Server monitor for host ~p can not start due to reason ~p", [Server#server_monitor.host, Reason]),
      {stop, {error, Reason}, State#state{connection = undefined}}
  end.



unlocked(_Event, State) ->
  {StateName, NewState} = get_next_state(State),

  if
    StateName /= unlocked ->
      [atlasd:lock_worker(Task) || Task <- (State#state.server)#server_monitor.tasks],
      [atlasd:lock_node(Node) || Node <- (State#state.server)#server_monitor.nodes];
    true -> ok
  end,

  {next_state, StateName, NewState, 10000}.

locked(_Event, State) ->
  {StateName, NewState} = get_next_state(State),

  if
    StateName /= locked ->
      [atlasd:unlock_worker(Task) || Task <- (State#state.server)#server_monitor.tasks],
      [atlasd:unlock_node(Node) || Node <- (State#state.server)#server_monitor.nodes];
    true -> ok
  end,

  {next_state, StateName, NewState, 10000}.


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

handle_event(disconnected, _StateName, State) ->
  {next_state, connect, State#state{connection = undefined}, 1};

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
  {reply, State, StateName, State, 10000};

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

connect_options(Auth) when Auth#server_monitor_auth.type == public_key ->
  [];
connect_options(Auth) when Auth#server_monitor_auth.type == password ->
  [{user, Auth#server_monitor_auth.user}, {password, Auth#server_monitor_auth.password}];
connect_options(_Auth) ->
  ?THROW_ERROR("Unexpected server auth function").


disconnect(SelfPid, Server, Reason) ->
  ?LOG("Server monitor for host ~p is disconnected with reason ~p", [Server#server_monitor.host, Reason]),
  gen_fsm:send_all_state_event(SelfPid, disconnected).

unexpected(Server, Message, _Peer) ->
  ?WARN("Unexpected message ~p arrives to server monitor for host ~p", [Message, Server#server_monitor.host]),
  skip.



ssh_exec(SshConnection, Command) ->
  {ok, SshChannel} = ssh_connection:session_channel(SshConnection, infinity),
  success = ssh_connection:exec(SshConnection, SshChannel, Command, infinity),
  Result = get_ssh_response(SshConnection),
  {ok, Result}.


get_ssh_response(ConnectionRef) ->
  get_ssh_response(ConnectionRef, []).

get_ssh_response(ConnectionRef, Data) ->
  receive
    {ssh_cm, ConnectionRef, Msg} ->
      case Msg of
        {closed, _ChannelId} ->
          Data;

        {data, _ChannelId, _DataType, Bin} ->
          get_ssh_response(ConnectionRef, Data ++ [Bin]);

        _ ->
          get_ssh_response(ConnectionRef, Data)
      end;

    _ ->
      get_ssh_response(ConnectionRef, Data)
  end.


get_next_state(State) ->
  Server = State#state.server,
  Watermark = (State#state.server)#server_monitor.watermark,

  La = get_server_load_avg(State),
  ?DBG("Server monitor detected LA ~p on host ~p", [La, Server#server_monitor.host]),

  Mem = get_server_memory_usage(State),
  ?DBG("Server monitor detected Memory usage ~p percents on host ~p", [Mem, Server#server_monitor.host]),

  NewState = State#state{la = La, mem = Mem},

  if
    (La > Watermark#server_monitor_watermark.la) or
      (Mem > Watermark#server_monitor_watermark.mem) ->
      {locked, NewState};
    true ->
      {unlocked, NewState}
  end.


get_server_load_avg(State) ->
  Server = State#state.server,
  {ok, Response} = ssh_exec(State#state.connection, "cat /proc/loadavg"),
  ?DBG("Server monitor recieve LA message ~p from host ~p", [Response, Server#server_monitor.host]),

  try
    [BinLa | _] = binary:split(Response, <<" ">>),
    binary_to_float(BinLa)
  catch
    _:_ -> 0
  end.

get_server_memory_usage(_State) -> 0.
