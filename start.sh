#!/bin/sh

ERL_LIBS=deps erl -pa ebin/ -eval "application:ensure_all_started(atlasd)" -config etc/app.config
