#!/bin/sh

ERL_LIBS=deps erl -pa deps/*/ebin ebin src/*/ebin/ -eval "application:ensure_all_started(atlasd)" -config etc/app2.config
