%%% -*- coding: utf-8 -*-
%%% Copyright (C) 2014 Alex Kazinskiy
%%%
%%% This file is part of Combats Battle Manager
%%%
%%% Author contact: alboo@list.ru

-record(error, {code, message}).

%%% ====================================================================
%%% Обработка ошибок
%%% ====================================================================

-define(CATCH_ERROR(Expr, Args),
	try Expr
	catch
		throw:{error, Error} ->
			erlang:error(Error, Args)
	end).

-define(THROW_ERROR(E), throw(E)).

%%% ====================================================================
%%% Коды ошибок
%%% ====================================================================
-define(ERROR_UNCOMPLETED, #error{code = -1, message = <<"Не реализовано"/utf8>>}).
-define(ERROR_WRONG_CALL, #error{code = 10, message = <<"Wrong call"/utf8>>}).
-define(ERROR_UNDEFINED, #error{code = 100, message = <<"Что-то пошло не так"/utf8>>}).
-define(ERROR_COOKIE, #error{code = 101, message = <<"Не указана cookie"/utf8>>}).
