%%%-------------------------------------------------------------------
%%% @author alex
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 10. Февр. 2016 14:37
%%%-------------------------------------------------------------------
-author("alex").


-record(rabbitmq_monitor_task, {
  task      :: string(),
  queue     :: string(),
  rake = 10 :: integer()
}).

-record(rabbitmq_monitor, {
  mode = api               :: api | native,
  host                     :: string(),
  port = "15672"           :: string(),
  user = "guest"           :: string(),
  pass = "guest"           :: string(),
  vhost = "%2f"            :: string(),
  exchange                 :: atom(),
  process_per_task = false :: boolean(),
  tasks = []               :: [#rabbitmq_monitor_task{}]
}).

-record(rabbitmq_queue, {
  name,
  messages,
  consumers,
  publish_rate,
  ack_rate
}).
