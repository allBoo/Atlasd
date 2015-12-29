#!/bin/sh

erl -noshell \
  -pa ebin ./deps/*/ebin \
  -s rabbitmq_api main $@ \
  -s init stops
