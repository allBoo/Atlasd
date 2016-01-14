%%%-------------------------------------------------------------------
%%% @author alboo
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 27. апр 2015 1:59
%%%-------------------------------------------------------------------
-module(cluster).
-author("alboo").

-behaviour(gen_server).
-include_lib("atlasd.hrl").

%% API
-export([start_link/0,
  connect/0,
  poll/1,
  poll/2,
  notify/1,
  notify/2,
  get_nodes/0,
  add_node/1,
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

-record(state, {node, nodes, known, bad, master}).

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

%% connect to all nodes
connect()->
  gen_server:call(?SERVER, connect, infinity).

%% send request to all known nodes
poll(Request) ->
  gen_server:call(?SERVER, {poll, Request}, infinity).

%% send request to Node
poll(Node, Request) when is_atom(Node) ->
  gen_server:call(?SERVER, {poll, Node, Request});

%% send request to Node
poll(Nodes, Request) when is_list(Nodes) ->
  gen_server:call(?SERVER, {poll, Nodes, Request}).

%% send async notification to all known nodes
notify(Message) ->
  gen_server:call(?SERVER, {notify, Message}, infinity).

%% send async notification to node
notify(Node, Message) ->
  gen_server:call(?SERVER, {notify, Node, Message}).

%% get list of connected nodes
get_nodes() ->
  gen_server:call(?SERVER, get_nodes).

%% add a new node to the cluster
add_node(Node) ->
  gen_server:call(?SERVER, {add_node, Node}).

%% remove node from the cluster
forget_node(Node) ->
  gen_server:call(?SERVER, {forget_node, Node}).

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
  Port = config:get("inet.port", 9100, integer),
  application:set_env(kernel, inet_dist_listen_min, Port),

  Node = list_to_atom(config:get("cluster.name", "atlasd") ++ "@" ++ config:get("inet.host", "127.0.0.1")),
  {ok, _} = net_kernel:start([Node, longnames]),

  Cookie = case config:get("cluster.cookie") of
    undefined ->
      ?THROW_ERROR(?ERROR_COOKIE);
    X -> list_to_atom(X)
  end,

  erlang:set_cookie(Node, Cookie),

  net_kernel:monitor_nodes(true),

  {ok, #state{node = Node, nodes = [Node], known = [Node]}}.

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

%% connect to all nodes
handle_call(connect, _From, State) ->
  Node = State#state.node,
  ClusterNodes = env:get('cluster.nodes', []),
  Nodes = case lists:member(Node, ClusterNodes) of
            true -> ClusterNodes;
            _ ->
              env:set('cluster.nodes', ClusterNodes ++ [Node]),
              ClusterNodes ++ [Node]
          end,
  ?DBG("Trying to connect to all known nodes ~p", [ClusterNodes]),

  %% close cluster for unknown nodes
  case env:get('cluster.solid') of
    true -> net_kernel:allow(Nodes ++ ['atlasctl@127.0.0.1']);
    _ -> ok
  end,

  [net_kernel:connect_node(N) || N <- Nodes],
  ok = global:sync(),

  reg:broadcast(node, self(), connected),
  {reply, ok, State#state{nodes = Nodes}};

%% add a new node
handle_call({add_node, Node}, _From, State) ->
  case lists:member(Node, env:get('cluster.nodes', [])) of
    true ->
      true = net_kernel:connect_node(Node),
      {reply, connected, State};

    _ ->
      Nodes = env:get('cluster.nodes', []) ++ [Node],
      case env:get('cluster.solid') of
        true -> net_kernel:allow(Nodes ++ ['atlasctl@127.0.0.1']);
        _ -> ok
      end,

      true = net_kernel:connect_node(Node),
      env:set('cluster.nodes', Nodes),

      {reply, connected, State#state{nodes = Nodes}}
  end;


%% remove node
handle_call({forget_node, Node}, _From, State) ->
  Nodes = env:get('cluster.nodes', []) -- [Node],
  env:set('cluster.nodes', Nodes),
  gen_server:cast({atlasd, Node}, stop),
  db_cluster:forget_node(Node),
  {reply, removed, State#state{nodes = Nodes}};


%% send sync request to all known nodes
handle_call({poll, Message}, _From, State) ->
  {Replies, BadNodes} = gen_server:multi_call(State#state.known, atlasd, Message),
  {reply, Replies, State#state{bad = BadNodes}};

%% send sync request to node
handle_call({poll, Node, Message}, _From, State) when is_atom(Node) ->
  {reply, gen_server:call({atlasd, Node}, Message, infinity), State};

%% send sync request to list of nodes
handle_call({poll, Nodes, Message}, _From, State) when is_list(Nodes) ->
  {Replies, BadNodes} = gen_server:multi_call(Nodes, atlasd, Message),
  {reply, Replies, State#state{bad = BadNodes}};

%% send async notification to all known nodes
handle_call({notify, Message}, _From, State) ->
  {reply, gen_server:abcast(State#state.known, atlasd, Message), State};

%% send async notification to node
handle_call({notify, Node, Message}, _From, State) ->
  {reply, gen_server:cast({atlasd, Node}, Message), State};

%% send async notification to node
handle_call(get_nodes, _From, State) ->
  {reply, State#state.known, State};

%%
handle_call(Request, _From, State) ->
  ?DBG("Missed call request ~p", [Request]),
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
handle_cast(Request, State) ->
  ?DBG("Missed cast request ~p", [Request]),
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

handle_info({nodeup, Node}, State) ->
  global:sync(),
  gen_server:cast(master, hello), %% forcibly run global names resolution
  Known = case lists:member(Node, State#state.known) of
            false ->
              ?DBG("Found new node ~p~n", [Node]),
              reg:broadcast(node, self(), {node, up, Node}),
              [Node | State#state.known];

            _ -> State#state.known
          end,

  {noreply, State#state{known = Known}};

handle_info({nodedown, Node}, State) ->
  ?DBG("Node down ~p~n", [Node]),
  reg:broadcast(node, self(), {node, down, Node}),

  {noreply, State#state{known = lists:delete(Node, State#state.known)}};


handle_info(Info, State) ->
  ?DBG("NET INFO ~p~n", [Info]),
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
