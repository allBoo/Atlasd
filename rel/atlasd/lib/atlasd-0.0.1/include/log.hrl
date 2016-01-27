%%% -*- coding: utf-8 -*-
%%% Copyright (C) 2014 Alex Kazinskiy
%%%
%%% This file is part of Combats Battle Manager
%%%
%%% Author contact: alboo@list.ru

-define(DBG(F, A), log:debug(F, A)).
-define(DBG(F), log:debug(F)).
-define(LOG(F, A), log:info(F, A)).
-define(LOG(F), log:info(F)).
-define(WARN(F, A), log:warning(F, A)).
-define(WARN(F), log:warning(F)).
-define(ERR(F, A), log:error(F, A)).
-define(ERR(F), log:error(F)).
