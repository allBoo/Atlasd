%%%-------------------------------------------------------------------
%%% @author alboo
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 04. июн 2015 0:13
%%%-------------------------------------------------------------------
-module(master_monitors_sup).
-author("alboo").

-behaviour(supervisor).
-include_lib("atlasd.hrl").

%% API
-export([
  start_link/0,
  get_running_monitors/0
]).

%% Supervisor callbacks
-export([init/1]).
-define(SERVER, ?MODULE).
%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  case global:whereis_name(?MODULE) of
    undefined -> supervisor:start_link({global, ?MODULE}, ?MODULE, []);
    Pid ->
      ?DBG("master_monitors_sup is already started ~p", [Pid]),
      ignore
  end.

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart frequency and child
%% specifications.
%%
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
  {ok, {SupFlags :: {RestartStrategy :: supervisor:strategy(),
    MaxR :: non_neg_integer(), MaxT :: non_neg_integer()},
    [ChildSpec :: supervisor:child_spec()]
  }} |
  ignore |
  {error, Reason :: term()}).

init([]) ->
  Monitors = get_master_monitors(),
  {ok, { {one_for_one, 5, 10}, Monitors} }.

get_running_monitors() ->
  lists:map(fun({MonitorName, Pid, _, [MonitorType]}) ->
              case MonitorType of
                monitor_rabbitmq ->
                  {MonitorName, Pid, MonitorType, gen_fsm:sync_send_all_state_event(Pid, get_data)}
              end
            end,
    supervisor:which_children({global, ?MODULE})).

%%%===================================================================
%%% Internal functions
%%%===================================================================

get_master_monitors() ->
  Monitors = config:monitors(),
  lists:flatmap(fun(Monitor) ->
    case apply(Monitor#monitor.name, mode, []) of
      master ->
        apply(Monitor#monitor.name, child_specs, [Monitor#monitor.config]);
      _ -> []
    end
  end, Monitors).
