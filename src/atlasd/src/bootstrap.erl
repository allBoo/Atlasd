%%%-------------------------------------------------------------------
%%% @author alex
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 18. Янв. 2016 14:45
%%%-------------------------------------------------------------------
-module(bootstrap).
-author("alex").
-include_lib("atlasd.hrl").

%% API
-export([start/0]).


start() ->
  init_logs(),
  ok.



init_logs() ->
  LogLevel = config:get('log.level', debug, atom),
  LogProcs = config:get('log.procs', false, boolean),
  ErrorLogLevel = if LogProcs -> info; true -> error end,

  lager:set_loglevel(log_lager_event, lager_console_backend, undefined, LogLevel),
  LogLevel == debug andalso LogProcs andalso lager:set_loglevel(lager_console_backend, debug),

  start_crash_log(config:get('log.crash', "crash.log", string)),

  %% add file handler
  add_file_handler(log_lager_event, config:get('log.file', "atlasd.log", string), LogLevel),
  add_file_handler(error_logger_lager_event, config:get('log.error', "error.log", string), ErrorLogLevel),

  ok.


start_crash_log(File) ->
  LogFile = filename:absname(config:get('path.logs', "/var/log/atlasd", string) ++ "/" ++ File),

  MaxBytes = case application:get_env(lager, crash_log_msg_size) of
               {ok, Val} when is_integer(Val) andalso Val > 0 -> Val;
               _ -> 65536
             end,
  RotationSize = case application:get_env(lager, crash_log_size) of
                   {ok, Val1} when is_integer(Val1) andalso Val1 >= 0 -> Val1;
                   _ -> 0
                 end,
  RotationCount = case application:get_env(lager, crash_log_count) of
                    {ok, Val2} when is_integer(Val2) andalso Val2 >=0 -> Val2;
                    _ -> 0
                  end,
  RotationDate = case application:get_env(lager, crash_log_date) of
                   {ok, Val3} ->
                     case lager_util:parse_rotation_date_spec(Val3) of
                       {ok, Spec} -> Spec;
                       {error, _} when Val3 == "" -> undefined; %% blank is ok
                       {error, _} ->
                         error_logger:error_msg("Invalid date spec for "
                         "crash log ~p~n", [Val3]),
                         undefined
                     end;
                   _ -> undefined
                 end,

  ChildSpec = {lager_crash_log, {lager_crash_log, start_link, [LogFile, MaxBytes,
                RotationSize, RotationDate, RotationCount]},
                permanent, 5000, worker, [lager_crash_log]},
  supervisor:start_child(lager_sup, ChildSpec).


add_file_handler(Sink, File, LogLevel) ->
  LogFile = filename:absname(config:get('path.logs', "/var/log/atlasd", string) ++ "/" ++ File),
  Handler = {lager_file_backend, LogFile},
  Config = [{file, LogFile}, {level, LogLevel}],
  lager_config:global_set(handlers,
    lager_config:global_get(handlers, []) ++
    [start_handler(Sink, Handler, Config)]),
  lager:update_loglevel_config(Sink).


start_handler(Sink, Module, Config) ->
  {ok, Watcher} = supervisor:start_child(lager_handler_watcher_sup,
                                         [Sink, Module, Config]),
  {Module, Watcher, Sink}.
