-module(atlasd_sup).

-behaviour(supervisor).
-include_lib("atlasd.hrl").

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    Children = [
        ?CHILD(config),
        ?CHILD(atlasd),
        ?CHILD(cluster)
    ],
    {ok, {{one_for_one, 5, 10}, Children}}.
