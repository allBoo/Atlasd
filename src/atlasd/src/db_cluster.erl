%%%-------------------------------------------------------------------
%%% @author alex
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 18. Дек. 2015 16:36
%%%-------------------------------------------------------------------
-module(db_cluster).
-author("alex").

-behaviour(gen_server).
-include_lib("atlasd.hrl").

%% API
-export([
  start_link/0,
  start_master/0,
  start_slave/0,
  add_nodes/1,
  forget_node/1
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
  role = slave :: master | slave,
  nodes = []
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
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).


%%--------------------------------------------------------------------
%% @doc
%% Become as a master
%%
%% @end
%%--------------------------------------------------------------------
start_master() ->
  gen_server:call(?SERVER, master).

%%--------------------------------------------------------------------
%% @doc
%% Become as a slave
%%
%% @end
%%--------------------------------------------------------------------
start_slave() ->
  gen_server:call(?SERVER, slave).


%%--------------------------------------------------------------------
%% @doc
%% Add new nodes to the cluster
%%
%% @end
%%--------------------------------------------------------------------
add_nodes(Nodes) ->
  gen_server:cast(?SERVER, {add_nodes, Nodes}).


%%--------------------------------------------------------------------
%% @doc
%% Remove node from cluster
%%
%% @end
%%--------------------------------------------------------------------
forget_node(Node) ->
  gen_server:cast(?SERVER, {forget_node, Node}).
  %mnesia:del_table_copy(schema, node@host.domain).

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
  start_database(),

  {ok, #state{}}.

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

handle_call(master, _From, State) when State#state.role == slave ->
  db_schema:ensure_schema(),
  mnesia:set_master_nodes([node()]),
  {reply, ok, State#state{nodes = mnesia:system_info(running_db_nodes), role = master}};


handle_call(slave, _From, State) when State#state.role == master ->
  {reply, ok, State#state{role = slave}};


%% delete database
handle_call(reset_database, _From, State) when State#state.role == slave ->
  db_schema:drop_schema(),
  Result = start_database(),

  {reply, Result, State};


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

handle_cast({add_nodes, Nodes}, State) when State#state.role == master ->
  DbNodes = do_add_nodes(Nodes),
  {noreply, State#state{nodes = DbNodes}};

handle_cast({forget_node, Node}, State) when State#state.role == master ->
  DbNodes = do_remove_node(Node),
  {noreply, State#state{nodes = DbNodes}};

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

start_database() ->
  DataPath = filename:absname(config:get("path.data", "/var/lib/atlasd", string)),
  case filelib:ensure_dir(DataPath) of
    ok ->
      case filelib:is_dir(DataPath) of
        true -> ok;
        false ->
          case file:make_dir(DataPath) of
            ok -> ok;
            {error, Reason} ->
              ?ERR("Can not create data dir with reason ~p", [Reason]),
              ?THROW_ERROR(?ERROR_DATA_PATH)
          end
      end;
    {error, Reason} ->
      ?ERR("Can not access data path with reason ~p", [Reason]),
      ?THROW_ERROR(?ERROR_DATA_PATH)
  end,

  ok = mnesia:start([{dir, DataPath}]).


do_add_nodes([]) -> mnesia:system_info(running_db_nodes);
do_add_nodes([Node | Tail]) ->
  RunningNodes = mnesia:system_info(running_db_nodes),
  case lists:member(Node, RunningNodes) of
    true -> ok;
    _ ->
      try_to_add_node(Node)
  end,
  do_add_nodes(Tail).

try_to_add_node(Node) ->
  ?DBG("Reset DB schema on node ~p and create new one", [Node]),
  gen_server:call({?MODULE, Node}, reset_database),

  case mnesia:change_config(extra_db_nodes, [Node]) of
    {ok, _} ->
      %% make database persistent
      mnesia:change_table_copy_type(schema, Node, disc_copies),

      ?DBG("New node ~p connected successfully. Start to copy tables", [Node]),
      copy_tables(Node);

    Error ->
      ?ERR("Error while connection to a new database with reason ~p", [Error]),
      ?THROW_ERROR(?ERROR_CONNECT_DB)
  end.

%% copy all tables
copy_tables(ToNode) ->
  copy_tables(ToNode, mnesia:system_info(tables)).

copy_tables(_, []) -> ok;
copy_tables(ToNode, [Table | Tables]) ->
  %% change schema copy type at begin to ensure that node has disc
  mnesia:change_table_copy_type(schema, ToNode, disc_copies),

  Nodes = mnesia:table_info(Table, where_to_commit),
  case lists:keyfind(node(), 1, Nodes) of
    {_, Type} ->
      %% if table already exists check copy type and change it if need
      case lists:keyfind(ToNode, 1, Nodes) of
        {ToNode, Type} ->
          ?DBG("Table ~p on node ~p already has the same copy type ~p", [Table, ToNode, Type]);
        {ToNode, AnotherType} ->
          Result = mnesia:change_table_copy_type(Table, ToNode, Type),
          ?DBG("Table ~p on node ~p has another copy type ~p. Change it to ~p with result ~p", [Table, ToNode, AnotherType, Type, Result]);
        _ ->
          Result = mnesia:add_table_copy(Table, ToNode, Type),
          ?DBG("Add table ~p copy as ~p to node ~p with result ~p", [Table, Type, ToNode, Result])
      end;

    _ ->
      ?DBG("Table ~p doesn`t exists on master node ~p", [Table, node()]),
      ignore
  end,
  copy_tables(ToNode, Tables).


do_remove_node(Node) ->
  ?DBG("Remove table copies from node ~p", [Node]),
  mnesia:del_table_copy(schema, Node),
  mnesia:system_info(running_db_nodes).
