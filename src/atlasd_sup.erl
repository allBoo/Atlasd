-module(atlasd_sup).

-behaviour(supervisor).
-include_lib("atlasd.hrl").

%% API
-export([start_link/0, start_child/1]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_child(ChildSpec) ->
    case supervisor:start_child(?MODULE, ChildSpec) of
        {error, Reason} ->
            ?LOG("Can not start child process with reason ~p", [Reason]),
            ?THROW_ERROR(?ERROR_SYSTEM_ERROR);
        _ -> ok
    end.


%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    {ok, { {one_for_one, 5, 10}, [?CHILD(config), ?CHILD(atlasd), ?CHILD(cluster)]} }.

