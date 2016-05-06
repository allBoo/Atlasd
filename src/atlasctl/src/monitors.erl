%%%-------------------------------------------------------------------
%%% @author user
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 26. Янв. 2016 11:45
%%%-------------------------------------------------------------------
-module(monitors).
-author("user").
-include_lib("atlasd.hrl").

%% API
-export([
  config/2,
  export/2,
  import/2,
  list/2
]).


config(Options, _Args) ->
  io:format("Monitor config values:~n", []),
  Config = atlasctl:get_runtime(Options, [get_monitors]),
  io:format("~p~n", [Config]).

list(Options, _Args) ->
  Node = atlasctl:connect(Options),
  Monitors = util:rpc_call(Node, get_monitors, []),
  io:format("Monitors ~p~n", [Monitors]).

export(Options, []) ->
  export(Options, [json]);

export(Options, Args) ->
  [Format | _] = Args,
  Config = atlasctl:get_runtime(Options, [get_monitors]),
  util:dbg("Config ~p~n", [Config]),
  Formatted = format(Config, list_to_atom(Format)),
  io:format("~p~n", [Formatted]).

format(Config, map) ->
  MonitorPrinter = ?record_to_map(monitor),
  lists:map(fun(El) ->
    MonitorRecord = MonitorPrinter(El),
    Record = maps:get(config, MonitorRecord, false),
    FormattedRecord = %if
                      %  is_record(Record, rabbitmq_monitor) ->
                          format_record(Record, rabbitmq_monitor),
                      %end,
    maps:put(config, FormattedRecord, MonitorRecord)
            end, Config);

format(Config, json) ->
  Map = format(Config, map),
  jiffy:encode(Map).

format_record(Record, rabbitmq_monitor) -> ok.
  %RabbitmqMonitorTaskPrinter = ?record_to_map(rabbitmq_monitor_task),
  %RabbitmqMonitorPrinter = ?record_to_map(rabbitmq_monitor),
  %RabbitmqMonitorPrinter(Record#rabbitmq_monitor{tasks = lists:map(fun(Task) ->
  %  RabbitmqMonitorTaskPrinter(Task)
  %                                                                 end, Record#rabbitmq_monitor.tasks)}).

import(_Options, []) ->
  util:err_msg("You must provide path to file or raw json");
import(Options, Args) ->
  [Arg | _] = Args,
  RawData = case filelib:is_file(Arg) of
              true ->
                {ok, Contents} = file:read_file(Arg),
                binary_to_list(Contents);

              _ -> Arg
            end,

  Data = jiffy:decode(RawData, [return_maps]),
  Node = atlasctl:connect(Options),
  Monitors = create_monitors_spec(Node, Data),
  ok = util:rpc_call(Node, set_monitors, [Monitors]).


create_monitors_spec(Node, Data) ->
  create_monitors_spec(Node, Data, []).

create_monitors_spec(_Node, [], Acc) -> Acc;
create_monitors_spec(Node, [Item | Tail], Acc) ->
  Name = binary_to_atom(maps:get(<<"name">>, Item), utf8),
  RawConfig = maps:get(<<"config">>, Item),
  Config = util:rpc_call(Node, Name, decode_config, [RawConfig]),

  Monitor = #monitor{
    name = Name,
    config = Config
  },
  [Monitor | create_monitors_spec(Node, Tail, Acc)].
