%%%-------------------------------------------------------------------
%%% @author alboo
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 27. апр 2015 1:39
%%%-------------------------------------------------------------------
-author("alboo").


%%% ====================================================================
%%% Main include file
%%% ====================================================================
-include_lib("log.hrl").
-include_lib("error.hrl").

%% Helper macro for declaring children of supervisor
-define(CHILD(I), {I, {I, start_link, []}, permanent, 5000, worker, [I]}).
-define(CHILD_SUP(I), {I, {I, start_link, []}, permanent, infinity, supervisor, [I]}).
