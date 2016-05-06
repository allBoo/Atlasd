%%%-------------------------------------------------------------------
%%% @author alex
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 10. Февр. 2016 14:00
%%%-------------------------------------------------------------------
-module(util).
-author("alex").

%% API
-export([
  format_boolean/1,
  format_integer/1,
  format_inf_integer/1
]).


format_boolean(X) when is_boolean(X) -> X;
format_boolean(<<"true">>) -> true;
format_boolean(_) -> false.

format_integer(X) when is_integer(X) -> X;
format_integer(X) -> binary_to_integer(X).

format_inf_integer(infinity) -> infinity;
format_inf_integer(<<infinity>>) -> infinity;
format_inf_integer(X) when is_integer(X) -> X;
format_inf_integer(X) -> binary_to_integer(X).
