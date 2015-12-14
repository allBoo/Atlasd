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
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

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
  supervisor:start_link({global, ?MODULE}, ?MODULE, []).

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

%%%===================================================================
%%% Internal functions
%%%===================================================================

get_master_monitors() ->
  lists:flatmap(fun({Monitor, Config}) ->
    MonitorModule = list_to_atom("monitor_" ++ Monitor),
    case apply(MonitorModule, mode, []) of
      master ->
        apply(MonitorModule, child_specs, [Config]);

      _ -> []
    end
  end, config:get("monitors")).