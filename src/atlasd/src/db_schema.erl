%%%-------------------------------------------------------------------
%%% @author alex
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 18. Дек. 2015 18:05
%%%-------------------------------------------------------------------
-module(db_schema).
-author("alex").
-include_lib("atlasd.hrl").



%% API
-export([
  ensure_schema/0,
  drop_schema/0
]).

-define(DB_VERSION, 2).

%%--------------------------------------------------------------------
%% @doc
%% Checks if database schema exists and create it if not
%%
%% @end
%%--------------------------------------------------------------------
ensure_schema() ->
  initial_setup(is_first_run()),
  migrate(),
  ok.


%%--------------------------------------------------------------------
%% @doc
%% Checks if database schema exists and create it if not
%%
%% @end
%%--------------------------------------------------------------------
drop_schema() ->
  mnesia:stop(),
  mnesia:delete_schema([node()]).


%%--------------------------------------------------------------------
%% @doc
%% check if env table exists.
%% if not this mean that this is first start
%% @end
%%--------------------------------------------------------------------
is_first_run() ->
  not lists:member(env, mnesia:system_info(tables)).

%%--------------------------------------------------------------------
%% @doc
%% setup database schema
%% @end
%%--------------------------------------------------------------------
initial_setup(false) -> ok;
initial_setup(true) ->
  %% check schema storage type and change to disc_copies
  case mnesia:table_info(schema, storage_type) of
    disc_copies -> ok;
    _ ->
      mnesia:change_table_copy_type(schema, node(), disc_copies)
  end,

  %% create env table and set DB Version to 0
  env:init(),
  env:set(db_version, 0),
  ok.


%%--------------------------------------------------------------------
%% @doc
%% run schema migrations
%% @end
%%--------------------------------------------------------------------
migrate() ->
  %% db version from env
  DbVersion = env:get(db_version),
  Migrations = lists:seq(DbVersion + 1, ?DB_VERSION),
  migrate(Migrations).

migrate([]) -> ok;
migrate([Version | Tail]) ->
  Module = list_to_atom("migration_" ++ integer_to_list(Version)),
  ?LOG("Try to apply database migration ~p", [Version]),
  apply(Module, up, []),
  env:set(db_version, Version),
  ?LOG("Database migration ~p applied successfully", [Version]),
  migrate(Tail).
