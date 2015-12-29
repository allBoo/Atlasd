%%%-------------------------------------------------------------------
%%% @author alboo
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 29. апр 2015 23:27
%%%-------------------------------------------------------------------
-module(worker_sup).
-author("alboo").

-behaviour(supervisor).
-include_lib("atlasd.hrl").

%% API
-export([
  start_link/1,
  get_worker/1,
  get_worker_name/1
]).

%% Supervisor callbacks
-export([init/1]).


-define(WORKER(A), {worker, {worker, start_link, [A]}, transient, 5000, worker, [worker]}).
-define(MONITOR(I, A), {I, {I, start_link, A}, transient, 5000, worker, [I]}).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link(Worker :: #worker{}) ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Worker) when is_record(Worker, worker) ->
  case supervisor:start_link(?MODULE, []) of
    {ok, SupPid} when is_pid(SupPid) ->
      %% start worker
      case supervisor:start_child(SupPid, ?WORKER(Worker)) of
        {ok, WorkerPid} when is_pid(WorkerPid) ->
          %% start monitors
          WorkerData = [SupPid, WorkerPid, Worker],
          {ok, _} = supervisor:start_child(SupPid, ?MONITOR(worker_monitor_default, WorkerData)),

          %% return supervisor ref
          {ok, SupPid};

        WorkerError ->
          ?DBG("Can not start worker due to ~p", [WorkerError]),
          WorkerError
      end;

    Err ->
      ?DBG("Can not start worker supervisor due to ~p", [Err]),
      Err
  end.


get_worker(SupRef) ->
  case lists:keyfind([worker], 4, supervisor:which_children(SupRef)) of
    {_, Pid, _, _} when is_pid(Pid) ->
      Pid;
    _ -> false
  end.


get_worker_name(SupRef) ->
  case get_worker(SupRef) of
    Pid when is_pid(Pid) ->
      {Pid, worker:get_name(Pid)};
    _ -> false
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
  {ok, { {one_for_one, 5, 10}, []} }.

%%%===================================================================
%%% Internal functions
%%%===================================================================
