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
-define(ERROR_SYSTEM_ERROR, #error{code = 1, message = "System error"}).
-define(ERROR_WRONG_CALL, #error{code = 10, message = <<"Wrong call"/utf8>>}).
-define(ERROR_UNDEFINED, #error{code = 100, message = <<"Что-то пошло не так"/utf8>>}).
-define(ERROR_COOKIE, #error{code = 101, message = <<"Не указана cookie"/utf8>>}).
-define(ERROR_CONFIG_NOT_FOUND, #error{code = 102, message = "Config file not found"}).
-define(ERROR_DATA_PATH, #error{code = 103, message = "Data path is not accessible"}).
-define(ERROR_CONNECT_DB, #error{code = 104, message = "Error while connecting to a new database"}).
-define(ERROR_QUERY, #error{code = 105, message = "Error while quering to a database"}).
