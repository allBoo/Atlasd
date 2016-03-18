%%%-------------------------------------------------------------------
%%% @author alboo
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 28. апр 2015 1:20
%%%-------------------------------------------------------------------
-module(workers_sup).
-author("alboo").

-behaviour(supervisor).
-include_lib("atlasd.hrl").

%% API
-export([
  start_link/0,
  start_worker/1,
  stop_worker/1,
  get_group_workers/1,
  get_workers/0,
  modify_group/3,
  update_groups/2
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
  supervisor:start_link({local, ?SERVER}, ?MODULE, []).


%%
start_worker(Worker) when is_record(Worker, worker) ->
  supervisor:start_child(?SERVER, [Worker]).

%%
stop_worker(WorkerPid) when is_pid(WorkerPid) ->
  %% search supervisor for current worker pid
  lists:takewhile(fun({_, WorkerSup, _, _}) ->
    case worker_sup:get_worker(WorkerSup) of
      WorkerPid ->
        % kill
        supervisor:terminate_child(?SERVER, WorkerSup),
        false;

      _ -> true
    end
  end, supervisor:which_children(?SERVER)),
  ok;

stop_worker(_) ->
  false.

get_group_workers(Group) ->
  lists:filtermap(fun({_, WorkerSup, _, _}) ->
      WorkerGroups = worker_sup:get_worker_groups(WorkerSup),
      case lists:member(Group, WorkerGroups) of
        true ->
          {true, worker_sup:get_worker_name(WorkerSup)};
        _ ->
          false
      end
    end, supervisor:which_children(?SERVER)).

update_groups(Groups, WorkerName) ->
  lists:foreach(fun({_, WorkerSup, _, _}) ->
                  {_, WorkerSupName, _} = worker_sup:get_worker_name(WorkerSup),
                  case WorkerName == WorkerSupName of
                    true ->
                      worker_sup:update_groups(WorkerSup, Groups);
                    _ ->
                      false
                  end
                end, supervisor:which_children(?SERVER)).

modify_group(Group, WorkerName, Action) ->
                lists:foreach(fun({_, WorkerSup, _, _}) ->
                  {_, WorkerSupName, _} = worker_sup:get_worker_name(WorkerSup),
                  case WorkerName == WorkerSupName of
                    true ->
                      worker_sup:modify_groups(WorkerSup, Group, Action);
                    _ ->
                      false
                  end
                end, supervisor:which_children(?SERVER)).

%%
get_workers() ->
  lists:map(fun({_, WorkerSup, _, _}) ->
    worker_sup:get_worker_name(WorkerSup)
  end, supervisor:which_children(?SERVER)).


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
  {ok, { {simple_one_for_one, 5, 10}, [
    {worker_sup, {worker_sup, start_link, []}, temporary, infinity, supervisor, [worker_sup]}
  ]}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
