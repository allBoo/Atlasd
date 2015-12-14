%%%-------------------------------------------------------------------
%%% @author alboo
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 28. апр 2015 1:24
%%%-------------------------------------------------------------------
-module(master_sup).
-author("alboo").

-behaviour(supervisor).
-include_lib("atlasd.hrl").

%% API
-export([start_link/0, start_monitors/0]).

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
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).


%% starts the monitors
start_monitors() ->
  %% kill instances of the running monitors
  case global:whereis_name(master_monitors_sup) of
    undefined -> ok;

    Pid ->
      supervisor:terminate_child({master_sup, node(Pid)}, master_monitors_sup),
      supervisor:delete_child({master_sup, node(Pid)}, master_monitors_sup)
  end,

  supervisor:start_child(?MODULE, ?CHILD_SUP(master_monitors_sup)).

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
  {ok, { {rest_for_one, 5, 10}, [?CHILD(master), ?CHILD(statistics), ?CHILD(balancer)]} }.

%%%===================================================================
%%% Internal functions
%%%===================================================================
