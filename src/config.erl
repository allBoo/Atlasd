%%%-------------------------------------------------------------------
%%% @author alboo
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 23. апр 2015 22:30
%%%-------------------------------------------------------------------
-module(config).
-author("alboo").

-behaviour(gen_server).
-include_lib("atlasd.hrl").

%% API
-export([start_link/0, get/1, get/2, get/3, workers/0]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {config}).

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
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

get(Key) ->
  gen_server:call(?MODULE, {get, Key}).

get(Key, Default) ->
  gen_server:call(?MODULE, {get, Key, Default}).

get(Key, Default, integer) ->
  case get(Key, Default) of
    I when is_integer(I) -> I;
    A when is_atom(A) -> list_to_integer(atom_to_list(A));
    L when is_list(L) -> list_to_integer(L);
    _ -> Default
  end;

get(Key, Default, atom) ->
  case get(Key, Default) of
    I when is_integer(I) -> list_to_atom(integer_to_list(I));
    A when is_atom(A) -> A;
    L when is_list(L) -> list_to_atom(L);
    _ -> Default
  end;

get(Key, Default, string) ->
  case get(Key, Default) of
    I when is_integer(I) -> integer_to_list(I);
    A when is_atom(A) -> atom_to_list(A);
    L when is_list(L) -> L;
    _ -> Default
  end;

get(Key, Default, boolean) ->
  case get(Key, Default) of
    true -> true;
    "true" -> true;
    false -> false;
    "false" -> false;
    I when is_integer(I) -> I =/= 0;
    _ -> Default
  end.


workers() ->
  parse_workers(config:get("workers")).

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
  {ok, #state{config = read_config(locate_config())}}.

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

handle_call({get, Key}, _From, State) ->
  Tokens = string:tokens(Key, "."),
  {reply, get_key_value(Tokens, State#state.config), State};

handle_call({get, Key, Default}, _From, State) ->
  Tokens = string:tokens(Key, "."),
  Result = case get_key_value(Tokens, State#state.config) of
    undefined ->
      Default;
    X ->
      X
  end,
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

locate_config() ->
  DefaultPaths = ["/etc/atlasd.yml", "etc/atlasd.yml", "/apps/atlasd/etc/atlasd.yml"],
  Paths = case application:get_env(atlasd, config) of
            {ok, P} -> [P | DefaultPaths];
            _ -> DefaultPaths
          end,

  Exists = lists:filtermap(fun(Path) ->
    case filelib:is_file(Path) and not filelib:is_dir(Path) of
      true -> {true, Path};
      _ -> false
    end
  end, Paths),
  select_config(Exists).

select_config([]) ->
  ?THROW_ERROR(?ERROR_CONFIG_NOT_FOUND);

select_config(Paths) ->
  lists:nth(1, Paths).

read_config(File) ->
  lists:nth(1, yamerl_constr:file(File)).

get_key_value([], Config) ->
  Config;

get_key_value([Key | Tokens], Config) when is_list(Tokens) ->
  case lists:keyfind(Key, 1, Config) of
    {Key, Values} ->
      get_key_value(Tokens, Values);
    _ ->
      undefined
  end.


%% workers config parser

parse_workers([]) ->
  [];
parse_workers(WorkersListCfg) ->
  [parse_worker(WorkerCfg) || WorkerCfg <- WorkersListCfg].

parse_worker({WorkerName, WorkerCfg}) ->
  parse_worker_config(#worker{name = list_to_atom(WorkerName)}, WorkerCfg).

parse_worker_config(Worker, []) ->
  Worker;

parse_worker_config(Worker, [{"command", Value} | WorkerCfg]) ->
  parse_worker_config(Worker#worker{command = Value}, WorkerCfg);

parse_worker_config(Worker, [{"priority", Value} | WorkerCfg]) when is_integer(Value) ->
  parse_worker_config(Worker#worker{priority = Value}, WorkerCfg);
parse_worker_config(Worker, [{"priority", Value} | WorkerCfg]) when is_list(Value) ->
  parse_worker_config(Worker#worker{priority = list_to_integer(Value)}, WorkerCfg);

parse_worker_config(Worker, [{"nodes", Value} | WorkerCfg]) when Value == any; Value == "any" ->
  parse_worker_config(Worker#worker{nodes = any}, WorkerCfg);
parse_worker_config(Worker, [{"nodes", Value} | WorkerCfg]) when is_list(Value) ->
  ?DBG("NODES ~p", [Value]),
  case io_lib:printable_list(Value) of
    true -> parse_worker_config(Worker#worker{nodes = [Value]}, WorkerCfg);
    _    -> parse_worker_config(Worker#worker{nodes = Value}, WorkerCfg)
  end;

parse_worker_config(Worker, [{"restart", Value} | WorkerCfg]) when Value == "disallow";
                                                                   Value == "simple";
                                                                   Value == "prestart" ->
  parse_worker_config(Worker#worker{restart = list_to_atom(Value)}, WorkerCfg);
parse_worker_config(Worker, [{"restart", Value} | WorkerCfg]) when Value == disallow;
                                                                   Value == simple;
                                                                   Value == prestart ->
  parse_worker_config(Worker#worker{restart = Value}, WorkerCfg);

parse_worker_config(Worker, [{"max_mem", infinity} | WorkerCfg]) ->
  parse_worker_config(Worker#worker{max_mem = infinity}, WorkerCfg);
parse_worker_config(Worker, [{"max_mem", Value} | WorkerCfg]) when is_integer(Value) ->
  parse_worker_config(Worker#worker{max_mem = {b, Value}}, WorkerCfg);
parse_worker_config(Worker, [{"max_mem", Value} | WorkerCfg]) when is_list(Value) ->
  case string:to_integer(Value) of
    {Kb, "K"} -> parse_worker_config(Worker#worker{max_mem = {k, Kb}}, WorkerCfg);
    {Mb, "M"} -> parse_worker_config(Worker#worker{max_mem = {m, Mb}}, WorkerCfg);
    {Gb, "G"} -> parse_worker_config(Worker#worker{max_mem = {g, Gb}}, WorkerCfg);
    _ ->
      ?LOG("Unknown worker max_mem config value ~p", [Value]),
      parse_worker_config(Worker, WorkerCfg)
  end;

parse_worker_config(Worker, [{"procs", Value} | WorkerCfg]) when is_list(Value) ->
  parse_worker_config(Worker#worker{procs = parse_procs_config(#worker_procs{}, Value)}, WorkerCfg);

parse_worker_config(Worker, [{"monitor", Value} | WorkerCfg]) when is_list(Value) ->
  parse_worker_config(Worker#worker{monitor = parse_monitor_configs(Value)}, WorkerCfg);

parse_worker_config(Worker, [Unknown | WorkerCfg]) ->
  ?LOG("Unknown worker config value ~p", [Unknown]),
  parse_worker_config(Worker, WorkerCfg).


%% worker procs config parser
parse_procs_config(Procs, []) ->
  Procs;

parse_procs_config(Procs, [{"min", Value} | ProcsConfig]) when is_integer(Value) ->
  parse_procs_config(Procs#worker_procs{min = Value}, ProcsConfig);
parse_procs_config(Procs, [{"max", Value} | ProcsConfig]) when is_integer(Value) ->
  parse_procs_config(Procs#worker_procs{max = Value}, ProcsConfig);
parse_procs_config(Procs, [{"allways", Value} | ProcsConfig]) when is_integer(Value) ->
  parse_procs_config(Procs#worker_procs{allways = Value}, ProcsConfig);
parse_procs_config(Procs, [{"max_per_node", Value} | ProcsConfig]) when is_integer(Value) ->
  parse_procs_config(Procs#worker_procs{max_per_node = Value}, ProcsConfig);
parse_procs_config(Procs, [{"each_node", Value} | ProcsConfig]) when is_integer(Value) ->
  parse_procs_config(Procs#worker_procs{each_node = Value}, ProcsConfig);

parse_procs_config(Procs, [Unknown | ProcsConfig]) ->
  ?LOG("Unknown worker procs config value ~p", [Unknown]),
  parse_procs_config(Procs, ProcsConfig).

%% worker monitor config parser

parse_monitor_configs([]) ->
  [];
parse_monitor_configs(MonitorsConfigs) ->
  [parse_monitor_config(#worker_monitor{name = MonitorName}, MonitorConfig) || {MonitorName, MonitorConfig} <- MonitorsConfigs].

%% @todo use monitor module to parse config
parse_monitor_config(Monitor, MonitorConfig) ->
  Monitor#worker_monitor{params = MonitorConfig}.

%parse_monitor_config(Monitor, [Unknown | MonitorConfig]) ->
%  ?LOG("Unknown worker monitor config value ~p", [Unknown]),
%  parse_monitor_config(Monitor, MonitorConfig).
