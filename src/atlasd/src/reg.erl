%%% -*- coding: utf-8 -*-
%%% Copyright (C) 2014 Alex Kazinskiy
%%%
%%% This file is part of Combats Battle Manager
%%%
%%% Author contact: alboo@list.ru

%%% ====================================================================
%%% Алиасы к gproc
%%% ====================================================================



-module(reg).
-include_lib("atlasd.hrl").

-define(TRY(Expr), try Expr, ok catch error:_Error -> error end).


%% ====================================================================
%% API functions
%% ====================================================================
-export([name/1, find/1, bind/1, unbind/1, binded/1, send/2, broadcast/3,
		 set/2, get/1, get/2]).


name(Names) when is_list(Names) ->
	KeyVal = lists:map(fun(Name) -> {Name, gproc:default(Name)} end, Names),
	?TRY(gproc:mreg(n, l, KeyVal));

name(Name) ->
	?TRY(gproc:add_local_name(Name)).

find(Name) ->
	gproc:lookup_local_name(Name).

bind(Names) when is_list(Names) ->
	KeyVal = lists:map(fun(Name) -> {Name, self()} end, Names),
	?TRY(gproc:mreg(p, l, KeyVal));

bind(Name) ->
	?TRY(gproc:add_local_property(Name, self())).

unbind(Names) when is_list(Names) ->
	?TRY(gproc:munreg({p, l, Names}));

unbind(Name) ->
	?TRY(gproc:unreg({p, l, Name})).

binded(Name) ->
	gproc:lookup_pids({p, l, Name}).

send(Name, Message) ->
	gproc:send({n, l, Name}, Message).

broadcast(Name, From, Message) ->
	gproc:send({p, l, Name}, {From, Message}).

set(Name, Value) ->
	?TRY(gproc:add_local_property(Name, Value)).

get(Name) ->
	case gproc:lookup_values({p, l, Name}) of
		[] -> undefined;
		[{_, Value} | _Tail] -> Value
	end.

get(Name, Default) ->
	case gproc:lookup_values({p, l, Name}) of
		[] -> Default;
		[{_, Value} | _Tail] -> Value
	end.

%% ====================================================================
%% Internal functions
%% ====================================================================


