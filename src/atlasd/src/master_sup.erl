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
-export([
  start_link/0,
  start_global_child/1,
  start_child/1,
  stop_child/1
]).

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
start_global_child(Module) ->
  %% kill instances of the running monitors
  case global:whereis_name(Module) of
    undefined -> ok;

    Pid ->
      supervisor:terminate_child({master_sup, node(Pid)}, Module),
      supervisor:delete_child({master_sup, node(Pid)}, Module)
  end,

  supervisor:start_child(?MODULE, ?CHILD_SUP_T(Module)).


start_child(Module) ->
  case whereis(Module) of
    undefined ->
      case supervisor:start_child(?MODULE, ?CHILD(Module)) of
        {error, Reason} ->
          ?ERR("Can not start child process with reason ~p", [Reason]),
          ?THROW_ERROR(?ERROR_SYSTEM_ERROR);
        _ -> ok
      end;

    Pid ->
      ?DBG("Process ~p is already started with pid ~p", [Module, Pid]),
      ok
  end.

stop_child(Module) ->
  supervisor:terminate_child(?MODULE, Module).

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
  {ok, { {rest_for_one, 5, 10}, [?CHILD(master), ?CHILD(statistics)]} }.

%%%===================================================================
%%% Internal functions
%%%===================================================================

