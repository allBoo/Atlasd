%%%-------------------------------------------------------------------
%%% @author user
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 25. Янв. 2016 14:12
%%%-------------------------------------------------------------------
-module(cluster_status).
-author("user").

-behaviour(gen_server).
-include_lib("atlasd.hrl").
%% API
-export([
  start_link/0,
  red/2,
  yellow/2,
  green/2,
  get_status/0,
  get_reasons/0
]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {
  reasons = []
}).
%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
  {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
  case global:whereis_name(?MODULE) of
    undefined ->
      gen_server:start_link({global, ?MODULE}, ?MODULE, [], []);
    Pid ->
      ?DBG("cluster_status is already started ~p", [Pid]),
      ignore
  end.


red(Reason, Comment) when is_atom(Reason) ->
  gen_server:call({global, ?SERVER}, {red, Reason, Comment}).
yellow(Reason, Comment) when is_atom(Reason) ->
  gen_server:call({global, ?SERVER}, {yellow, Reason, Comment}).
green(Reason, Comment) when is_atom(Reason) ->
  gen_server:call({global, ?SERVER}, {green, Reason, Comment}).
get_status() ->
  gen_server:call({global, ?SERVER}, get_status).
get_reasons() ->
  gen_server:call({global, ?SERVER}, get_reasons).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
  {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term()} | ignore).
init([]) ->
  {ok, #state{reasons = []}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
  {reply, Reply :: term(), NewState :: #state{}} |
  {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
  {stop, Reason :: term(), NewState :: #state{}}).


handle_call({Color, Reason, Comment}, _From, State) ->
  ReasonsMap = maps:from_list(State#state.reasons),
  {reply, ok, State#state{reasons = maps:to_list(maps:put(Reason, {Color, Comment}, ReasonsMap))}};


handle_call(get_status, _From, State) ->
  Red = [Color || {_, {Color, _}} <- State#state.reasons, Color == red],
  Yellow = [Color || {_, {Color, _}} <- State#state.reasons, Color == yellow],
  Green = [Color || {_, {Color, _}} <- State#state.reasons, Color == green],

  if
    length(Red) > 0 ->
      {reply, red, State};
    length(Yellow) > 0 ->
      {reply, yellow, State};
    length(Green) > 0 ->
      {reply, green, State};
    true ->
      empty
  end;

handle_call(get_reasons, _From, State) ->
  {reply, State#state.reasons, State};

handle_call(_Request, _From, State) ->
  {reply, ok, State}.
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_cast(_Request, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
  {noreply, NewState :: #state{}} |
  {noreply, NewState :: #state{}, timeout() | hibernate} |
  {stop, Reason :: term(), NewState :: #state{}}).
handle_info(_Info, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) ->
  {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
