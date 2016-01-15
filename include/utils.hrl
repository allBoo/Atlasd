%%%-------------------------------------------------------------------
%%% @author alex
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 15. Янв. 2016 11:08
%%%-------------------------------------------------------------------
-author("alex").

%%% This macro will create a function that converts a record to
%%% a {key, value} list (a proplist)

-define(record_to_list(Record),
  fun(Val) ->
    Fields = record_info(fields, Record),
    [_Tag| Values] = tuple_to_list(Val),
    lists:zip(Fields, Values)
  end
).

-define(record_to_map(Record),
  fun(Val) ->
    Fields = record_info(fields, Record),
    [_Tag| Values] = tuple_to_list(Val),
    maps:from_list(lists:zip(Fields, Values))
  end
).