%%% -*- coding: utf-8 -*-
%%% Copyright (C) 2014 Alex Kazinskiy
%%%
%%% This file is part of Combats Battle Manager
%%%
%%% Author contact: alboo@list.ru

-define(DBG(F, A), io:format("(~p ~w:~b) " ++ F ++ "~n", [self(), ?MODULE, ?LINE | A])).
%-define(DBG(F, A), ok).
-define(LOG(F, A), io:format("(~p ~w:~b) " ++ F ++ "~n", [self(), ?MODULE, ?LINE | A])).