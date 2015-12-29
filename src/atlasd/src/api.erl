-module(api).
-include_lib("elli/include/elli.hrl").

-export([start_link/0, auth_fun/3]).

start_link() ->
  BasicauthConfig = [
    {auth_fun, fun api:auth_fun/3},
    {auth_realm, <<"Admin Area">>} % optional
  ],

  Config = [
    {mods, [
      {elli_basicauth, BasicauthConfig},
      {api_callback, []}
    ]}
  ],

  {ok, IPTupled}  = inet_parse:address(config:get("http.host", "127.0.0.1")),

  elli:start_link([
    {callback, elli_middleware},
    {callback_args, Config},
    {ip, IPTupled},
    {port, config:get("http.port", 9900)},
    {min_acceptors, 5} % стандартно там 20, если что
  ]).


auth_fun(Req, User, Password) ->
  case elli_request:path(Req) of
    [<<"hello">>, <<"world">>] -> password_check(User, Password);
    _                 -> ok
  end.

password_check(User, Password) ->
  case {User, Password} of
    {undefined, undefined}      -> unauthorized;
    {<<"admin">>, <<"admin">>}  -> ok;
    {User, Password}            -> forbidden
  end.