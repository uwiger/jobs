%%==============================================================================
%% Copyright 2014 Ulf Wiger
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%==============================================================================

%%-------------------------------------------------------------------
%% File    : jobs_server.erl
%% @author  : Ulf Wiger <ulf@wiger.net>
%% @end
%% Description :
%%
%% Created : 15 Jan 2010 by Ulf Wiger <ulf@wiger.net>
%%-------------------------------------------------------------------
-module(jobs_server).
-behaviour(gen_server).

-export([ask/0,
         ask/1,
         run/1, run/2,
         done/1,
	 enqueue/2,
	 dequeue/2]).

-export([set_modifiers/1]).

-export([ask_queue/2]).

%% Config API
-export([add_queue/2,
	 modify_queue/2,
         delete_queue/1,
         add_counter/2,
         modify_counter/2,
         delete_counter/1,
         add_group_rate/2,
         modify_group_rate/2,
         delete_group_rate/1,
         info/1,
         queue_info/1,
	 queue_info/2,
         modify_regulator/4]).


-export([timestamp/0,
         timestamp_to_datetime/1]).

-export([start_link/0,
         start_link/1]).
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).


-import(proplists, [get_value/3]).

-include("jobs.hrl").
-record(st, {queues      = []  :: [#queue{}],
	     group_rates = []  :: [#grp{}],
	     counters    = []  :: [#cr{}],
	     monitors,
	     q_select          :: atom(),
	     q_select_st       :: any(),
	     default_queue,
	     info_f}).


-define(SERVER, ?MODULE).

-type queue_name() :: any().
-type info_category() :: queues | group_rates | counters.

-spec ask() -> {ok, any()} | {error, rejected | timeout}.
%%
ask() ->
    ask(default).


-spec ask(job_class()) -> {ok, reg_obj()} | {error, rejected | timeout}.
%%
ask(Type) ->
    call(?SERVER, {ask, Type}, infinity).

-spec run(fun(() -> X)) -> X.
%%
run(Fun) when is_function(Fun, 0) ->
    run(undefined, Fun).

-spec run(job_class(), fun(() -> X)) -> X.
%%
run(Type, Fun) when is_function(Fun, 0) ->
    case ask(Type) of
        {ok, Opaque} ->
            try Fun()
                after
                    done(Opaque)
                end;
        {error,Reason} ->
            erlang:error(Reason)
    end;
run(Type, Fun) when is_function(Fun, 1) ->
    case ask(Type) of
        {ok, Opaque} ->
            try Fun(Opaque)
                after
                    done(Opaque)
                end;
        {error,Reason} ->
            erlang:error(Reason)
    end.

-spec done(reg_obj()) -> ok.
%%
done({undefined, _}) ->
    %% no monitoring on this job (e.g. from a {action, approve} queue)
    ok;
done(Opaque) ->
    gen_server:cast(?MODULE, {done, self(), del_info(Opaque)}).

del_info({Ref, L}) ->
    {Ref, lists:keydelete(info, 1, L)}.


-spec enqueue(job_class(), any()) -> ok.
%%
enqueue(Type, Item) ->
    call(?SERVER, {enqueue, Type, Item}, infinity).

-spec dequeue(job_class(), integer() | infinity) -> [{timestamp(), any()}].
%%
dequeue(Type, N) when N==infinity; is_integer(N), N > 0 ->
    call(?SERVER, {dequeue, Type, N}, infinity).


-spec add_queue(queue_name(), [option()]) -> ok.
%%
add_queue(Name, Options) ->
    call(?SERVER, {add_queue, Name, Options}).

-spec modify_queue(queue_name(), [option()]) -> ok.
%%
modify_queue(Name, Options) ->
    call(?SERVER, {modify_queue, Name, Options}).

-spec delete_queue(queue_name()) -> ok.
delete_queue(Name) ->
    call(?SERVER, {delete_queue, Name}).


%% @spec ask_queue(QName, Request) -> Reply
%% @doc Invoke the Q:handle_call/3 function (if it exists).
%%
%% Send a request to a specific queue in the JOBS server.
%% Each queue has its own local state, allowing it to collect special statistics.
%% This function allows a client to send a request that is handled by a specific
%% queue instance, either to pull information from the queue, or to influence its
%% state.
%% @end
%%
-spec ask_queue(queue_name(), any()) -> any().
ask_queue(QName, Request) ->
    call(?SERVER, {ask_queue, QName, Request}).

-spec info(info_category()) -> [any()].
info(Item) ->
    call(?SERVER, {info, Item}).

queue_info(Name) ->
    call(?SERVER, {queue_info, Name}).

queue_info(Name, Item) ->
    call(?SERVER, {queue_info, Name, Item}).

add_group_rate(Name, Options) ->
    call(?SERVER, {add_group_rate, Name, Options}).

modify_group_rate(Name, Opts) ->
    call(?SERVER, {modify_group_rate, Name, Opts}).

delete_group_rate(Name) ->
    call(?SERVER, {delete_group_rate, Name}).

modify_regulator(Type, QName, RegName, Opts) ->
    call(?SERVER, {modify_regulator, Type, QName, RegName, Opts}).

add_counter(Name, Options) ->
    call(?SERVER, {add_counter, Name, Options}).

modify_counter(Name, Opts) ->
    call(?SERVER, {modify_counter, Name, Opts}).

delete_counter(Name) ->
    call(?SERVER, {delete_counter, Name}).



%% Sampler API
%%
set_modifiers(Modifiers) ->
    call(?SERVER, {set_modifiers, Modifiers}).


%% Client-side call function
%%
call(Server, Req) ->
    call(Server, Req, infinity).

call(Server, Req, Timeout) ->
    case gen_server:call(Server, Req, Timeout) of
        badarg ->
            erlang:error(badarg);
	{badarg, Reason} ->
	    erlang:error(Reason);
        Res ->
            Res
    end.


%% Reply functions called by the server

%% approve(From) ->
%%     approve(From, []).

approve(From, Counters) ->
    gen_server:reply(From, {ok, Counters}).


reject(From) ->
    gen_server:reply(From, {error, rejected}).

timeout({_, {Pid,Ref} = From}) when is_pid(Pid), is_reference(Ref) ->
    gen_server:reply(From, {error, timeout}).


%% start function

-spec start_link() -> {ok, pid()}.
%%
start_link() ->
    start_link(options()).

-spec start_link([option()]) -> {ok, pid()}.
%%
start_link(Opts0) when is_list(Opts0) ->
    Opts = expand_opts(sort_groups(group_opts(Opts0))),
    gen_server:start_link({local,?MODULE}, ?MODULE, Opts, []).

%% Server-side callbacks and helpers

-spec options() -> [{_Ctxt :: env | opts, _App:: user | atom(), [option()]}].
options() ->
    JobsOpts = {env, jobs, application:get_all_env(jobs)},
    Other = try [{env, A, Os} || {A, Os} <- setup:find_env_vars(jobs)]
	    catch
		error:undef -> []
	    end,
    [JobsOpts | Other].

group_opts([{_,_,_} = H|T]) ->
    [H|group_opts(T)];
group_opts([{_,_}|_] = Opts) ->
    {U, Rest} = lists:splitwith(fun(X) -> size(X) == 2 end, Opts),
    [{opts, user, U}|group_opts(Rest)];
group_opts([]) ->
    [].

sort_groups(Gs) ->
    %% How to give priority to certain 'global' options?
    %% 1. Options specified explicitly in Options
    %% 2. Options specified as 'jobs' environment variables
    %%    (there are none by default)
    %% 3. Options in other apps, as returned by 'setup:find_env_vars/1'
    %%
    %% Note that, as of now, we 'lift' all user options to the fore, even if
    %% they appear mixed in the argument given to jobs_server:start_link/1.
    %%
    User = [U || {opts, user, _} = U <- Gs],
    [Jobs] = [J || {env, jobs, _} = J <- Gs],
    User ++ [Jobs | Gs -- [Jobs | User]].

-spec expand_opts([option()]) -> [option()].
%%
expand_opts([{Ctxt, A, Opts}|T]) ->
    Exp = try expand_opts_(Opts)
	  catch
	      throw:{{error,R}, Arg} ->
		  error(R, [{context, Ctxt}, {app, A} | Arg])
	  end,
    [{Ctxt, A, Exp}|expand_opts(T)];
expand_opts([]) ->
    [].

expand_opts_([{config, F}|Opts]) ->
    case file:script(F) of
	{ok, NewOpts} ->
	    NewOpts ++ expand_opts_(Opts);
	{error, _} = E ->
	    throw({E, [{config,F}]})
    end;
expand_opts_([H|T]) ->
    [H|expand_opts_(T)];
expand_opts_([]) ->
    [].


standard_rate(R) when is_integer(R), R >= 0 ->
    [{regulators,
      [{rate,
	[{limit, R},
	 {modifiers, standard_modifiers()}]
       }]
     }].

standard_counter(N) when is_integer(N), N >= 0 ->
    [{regulators,
      [{counter,
	[{limit, N},
	 {modifiers, standard_modifiers()}]
       }]
     }].

-spec standard_modifiers() -> [q_modifier(),...].
%%
standard_modifiers() ->
    [{cpu, 10},
     {memory, 10}].

-spec init([option()]) -> {ok, #st{}}.
%%
init(Opts) ->
    process_flag(priority,high),
    S0 = #st{},
    [Qs, Gs, Cs] =
	[get_all_values(K,Opts,Def)
	 || {K,Def} <- [{queues     , [{default,[]}]},
			{group_rates, []},
			{counters   , []}]],
    Groups = init_groups(Gs),
    Counters = init_counters(Cs),
    S1 = S0#st{group_rates = Groups,
	       counters    = Counters},
    Queues = init_queues(Qs, S1),
    Default0 = case Queues of
                   [] ->
                       undefined;
                   [#queue{name = N}|_] ->
                       N
               end,
    Default = get_first_value(default_queue, Opts, Default0),
    {ok, set_info(
	   kick_producers(
	     lift_counters(S1#st{queues        = Queues,
				 default_queue = Default,
				 monitors = ets:new(monitors,[set])})))}.



init_queues(Qs, S) ->
    lists:map(fun(Q) ->
		      init_queue(Q,S)
	      end, Qs).

init_queue({Name, standard_rate, R}, S) when is_integer(R), R > 0 ->
    init_queue({Name, standard_rate(R)}, S);
init_queue({Name, standard_counter, N}, S) when is_integer(N), N > 0 ->
    init_queue({Name, standard_counter(N)}, S);
init_queue({Name, passive, Opts}, S) ->
    init_queue({Name, [{type, {passive, fifo}} | Opts]}, S);
init_queue({Name, Action}, _S) when Action==approve; Action==reject ->
    #queue{name = Name, type = {action, Action}};
init_queue({Name, producer, F, Opts}, S) ->
    init_queue({Name, [{type, {producer, F}} | Opts]}, S);
init_queue({Name, Opts0}, S) when is_list(Opts0) ->
    %% Allow the regulators to be named at the top-level.
    %% This makes it possible to write {q, [{counter, [{limit,1}]}]},
    %% instead of {q, [{regulators, [{counter, [{limit,1}]}]}]}.
    {Regs0, Opts} = lists:foldr(
		       fun(X, {R,O}) when is_tuple(X) ->
			       case lists:member(
				      element(1,X), [counter, rate,
						     named_counter,
						     group_rate]) of
				   true  -> {[X|R], O};
				   false -> {R, [X|O]}
			       end;
			  (X, {R, O}) -> {R, [X|O]}
		       end, {[], []}, normalize_options(Opts0)),
    [ChkI, Regs] =
        [get_value(K,Opts,D) ||
            {K, D} <- [{check_interval,undefined},
                       {regulators, Regs0}]],
    Q0 = q_new([{name,Name}|Opts]),
    Q1 = init_regulators(Regs, Q0#queue{check_interval = ChkI}),
    calculate_check_interval(Q1, S).

normalize_options(Opts) ->
    merge_regulators(
      lists:flatmap(
	fun({standard_rate, R}) when is_integer(R), R >= 0 ->
		standard_rate(R);
	   ({standard_counter, C}) when is_integer(C), C >= 0 ->
		standard_counter(C);
	   ({producer, F}) ->
		[{type, {producer, F}}];
	   (passive) ->
		[{type, {passive, fifo}}];
	   (A) when A==approve; A==reject ->
		[{type, {action, approve}}];
	   ({action, A}) when A==approve; A==reject ->
		[{type, {action, approve}}];
	   ({K, V}) ->
		[{K, V}]
	end, Opts)).

merge_regulators(Opts) ->
    merge_regulators(lists:keytake(regulators, 1, Opts), Opts, []).

merge_regulators(false, Opts, []) ->
    Opts;
merge_regulators(false, Opts, Regs) ->
    [{regulators, Regs}|Opts];
merge_regulators({value, {regulators, Rs}, Opts}, _, Acc) ->
    merge_regulators(lists:keytake(regulators, 1, Opts), Opts,
		     Acc ++ Rs).

calculate_check_interval(#queue{regulators = Rs,
				check_interval = undefined} = Q, S) ->
    Regs = expand_regulators(Rs, S),
    I = lists:foldl(
          fun(R, Acc) ->
		  Rate = get_rate(R),
                  erlang:min(Rate#rate.interval, Acc)
          end, infinity, Regs),
    Q#queue{check_interval = I};
calculate_check_interval(Q, _) ->
    Q.

init_groups(Gs) ->
    lists:map(
      fun({Name, Opts}) ->
              init_group(Opts, #grp{name = Name})
      end, Gs).

init_group(Opts, G) ->
    R = #rate{},
    Limit = get_value(limit, Opts, R#rate.limit),
    Modifiers = get_value(modifiers, Opts, R#rate.modifiers),
    Interval = interval(Limit),
    G#grp{rate = #rate{limit = Limit,
		       preset_limit = Limit,
		       modifiers = Modifiers,
		       interval = Interval}}.

init_counters(Cs) ->
    lists:map(
      fun({Name, Opts}) ->
              init_counter([{name, Name}|Opts], #cr{name   = Name,
                                                    shared = true})
      end, Cs).

init_regulators(Rs, #queue{name = Qname} = Q) ->
    {Rs1,_} = lists:mapfoldl(
		fun({rate, Opts}, {Rx,Cx}) ->
			Name0 = {rate,Qname,Rx},
			R0 = #rate{},
			RR0 = #rr{name = Name0, rate = R0},
                        {init_rate_regulator(Opts, RR0), {Rx+1, Cx}};
		   ({counter, Opts}, {Rx,Cx}) when is_list(Opts) ->
			Name0 = {counter,Qname,Cx},
			Name = get_value(name, Opts, Name0),
			{init_counter(Opts, #cr{name = Name,
						owner = Qname}), {Rx,Cx+1}};
		   ({named_counter, Name, Incr}, {Rx,Cx}) when is_integer(Incr) ->
			{#counter{name = Name, increment = Incr}, {Rx,Cx+1}};
		   ({group_rate, R} = Link, Acc) when is_atom(R) ->
			{Link, Acc}
		   %% ({counter, R} = Link, Acc) when is_atom(R) ->
		   %% 	{Link, Acc}
		end, {1,1}, Rs),
    case [RR || #rr{} = RR <- Rs1] of
        [_,_|_] = Multiples ->
            erlang:error(only_one_rate_regulator_allowed, Multiples);
        _ ->
            ok
    end,
    Q#queue{regulators = Rs1}.

init_rate_regulator(Opts, #rr{rate = R} = RR) ->
    [Limit,Modifiers,Name] =
        [get_value(K,Opts,D) ||
            {K,D} <- [{limit  , R#rate.limit},
                      {modifiers, R#rate.modifiers},
                      {name   , RR#rr.name}]],
    Interval = interval(Limit),
    RR#rr{name = Name,
          rate = #rate{limit = Limit,
                       interval = Interval,
                       preset_limit = Limit,
                       modifiers = Modifiers}}.


%% init_counter(Opts) ->
%%     init_counter(Opts, #cr{}).

init_counter(Opts, #cr{} = CR0) ->
    R = #rate{},
    Limit = get_value(limit, Opts, R#rate.limit),
    Interval = get_value(interval, Opts, ?COUNTER_SAMPLE_INTERVAL),
    Increment = get_value(increment, Opts, 1),
    Modifiers = get_value(modifiers, Opts, R#rate.modifiers),
    CR0#cr{rate = #rate{limit = Limit,
			interval = Interval,
			preset_limit = Limit,
			modifiers = Modifiers},
	   increment = Increment}.

lift_counters(#st{queues = Qs} = S) ->
    lists:foldl(fun do_lift_counters/2, S, Qs).

do_lift_counters(#queue{name = Name, regulators = Rs} = Q,
		 #st{queues = Queues, counters = Counters} = S0) ->
    Aliases = [A || #counter{name = A} <- Rs],
    S = lift_aliases(Aliases, Name, S0),
    case [R || #cr{} = R <- Rs] of
	[] ->
	    S;
	[_|_] = CRs ->
	    {Rs1, Cs1} = lists:foldl(fun(CR,Acc) ->
					     mk_counter_alias(CR,Acc,Name)
				     end, {Rs, Counters}, CRs),
	    Q1 = Q#queue{regulators = Rs1},
	    Queues1 = lists:keyreplace(Name, #queue.name, Queues, Q1),
	    S#st{queues = Queues1, counters = Cs1}
    end.

lift_aliases([], _, S) ->
    S;
lift_aliases(Aliases, QName, #st{counters = Cs} = S) ->
    Cs1 = lists:foldl(
	    fun(Alias, Csx) ->
		    case lists:keyfind(Alias, #cr.name, Csx) of
			false ->
			    %% aliased counter doesn't exist...
			    %% We should probably issue a warning.
			    Csx;
			#cr{queues = Queues} = Existing ->
			    Qs = [QName|Queues -- [QName]],
			    lists:keyreplace(Alias, #cr.name, Csx,
					     Existing#cr{queues = Qs})
		    end
	    end, Cs, Aliases),
    S#st{counters = Cs1}.

mk_counter_alias(#cr{name = Name,
		     increment = I} = CR, {Rs, Cs}, QName) ->
    Alias = #counter{name = Name, increment = I},
    Rs1 = lists_replace(CR, Rs, Alias),
    case lists:keyfind(Name, #cr.name, Cs) of
	false ->
	    {Rs1, [CR#cr{queues = [QName]}|Cs]};
	#cr{queues = Queues} = Existing ->
	    Qs = [QName|Queues -- [QName]],
	    {Rs1, lists:keyreplace(Name, #cr.name, Cs,
				   Existing#cr{queues = Qs})}
    end.

pickup_aliases(Queues, #cr{name = N} = CR) ->
    QNames = lists:foldl(
	       fun(#queue{name = QName, regulators = Rs}, Acc) ->
		       case [1 || #counter{name = Nx} <- Rs, Nx =:= N] of
			   [] ->
			       Acc;
			   [_|_] ->
			       [QName | Acc]
		       end
	       end, [], Queues),
    CR#cr{queues = QNames}.

lists_replace(X, [X | T], With) -> [With | T];
lists_replace(X, [A | T], With) -> [A | lists_replace(X, T, With)].


-spec interval(integer()) -> undefined | float().
%%
%% Return the sampling interval (in ms) based on max frequency.
%% If max frequency is 0, we choose what corresponds to an unlimited interval
%%
interval(0    ) -> undefined;  % greater than any int()
interval(Limit) ->
    1000 / Limit.

set_info(S) ->
    %% We need to clear the info_f attribute, to
    %% avoid recursively inheriting all previous states.
    S1 = S#st{info_f = undefined},
    S1#st{info_f = fun(Q) ->
			   get_info(Q, S1)
		   end}.


%% Gen_server callbacks
handle_call(Req, From, S) ->
    try i_handle_call(Req, From, S) of
        {noreply, #st{} = S1} ->
            {noreply, set_info(S1)};
        {reply, R, #st{} = S1} ->
            {reply, R, set_info(S1)}
    catch
        error:Reason ->
	    io:fwrite("caught Reason = ~p~n", [{Reason, erlang:get_stacktrace()}]),
            error_report([{error, Reason},
                          {request, Req},
			  {stacktrace, erlang:get_stacktrace()}]),
            {reply, badarg, S}
    end.

i_handle_call({ask, Type}, From, #st{queues = Qs} = S) ->
    TS = timestamp(),
    {Qname, S1} = select_queue(Type, TS, S),
    case get_queue(Qname, Qs) of
        #queue{type = #action{a = approve}, stateful = undefined,
	       approved = Approved} = Q ->
	    S2 = S1#st{queues = lists:keyreplace(
				  Qname, #queue.name, Qs,
				  Q#queue{approved = Approved + 1})},
	    approve(From, {undefined, []}), {noreply, S2};
        #queue{type = #action{a = approve}, stateful = Stf,
	       approved = Approved} = Q ->
	    {Val, Stf1} = update_stateful(Stf, [], S1#st.info_f),
	    S2 = S1#st{queues = lists:keyreplace(
				  Qname, #queue.name, Qs,
				  Q#queue{stateful = Stf1,
					  approved = Approved + 1})},
	    approve(From, {undefined, [{info, Val}]}), {noreply, S2};
	#queue{type = #action{a = reject}} ->
	    reject(From), {noreply, S1};
	#queue{type = #producer{}} ->
	    {reply, badarg, S1};
        #queue{} = Q ->
            {Q2, S2} = queue_job(TS, From, Q, S1),
	    {noreply, update_queue(Q2, S2)};
        false ->
            {reply, badarg, S1}
    end;
i_handle_call({enqueue, Type, Item}, _From, #st{queues = Qs} = S) ->
    TS = timestamp(),
    {Qname, S1} = select_queue(Type, TS, S),
    case get_queue(Qname, Qs) of
	#queue{type = {passive, _}, waiters = Ws} = Q ->
	    case Ws of
		[] ->
		    {Result, S2} = do_enqueue(TS, Item, Q, S1),
		    {reply, Result, S2};
		[From|Ws1] ->
		    gen_server:reply(From, [{TS, Item}]),
		    {reply, ok, update_queue(Q#queue{waiters = Ws1}, S)}
	    end;
	_ ->
	    {reply, badarg, S1}
    end;
i_handle_call({dequeue, Type, N}, From, #st{queues = Qs} = S) ->
    {Qname, _S1} = select_queue(Type, undefined, S),
    case get_queue(Qname, Qs) of
	#queue{type = #passive{}, waiters = Ws} = Q ->
	    {Items, Q1} = q_out(N, Q),
	    case Items of
		[] ->
		    {noreply, update_queue(Q1#queue{waiters = Ws ++ [From]}, S)};
		Jobs ->
		    {reply, Jobs, update_queue(Q1, S)}
	    end;
	_Other ->
	    io:fwrite("get_queue(~p, ~p) -> ~p~n", [Qname, Qs, _Other]),
	    {reply, badarg, S}
    end;
i_handle_call({set_modifiers, Modifiers}, _, #st{queues     = Qs,
						 group_rates = GRs,
						 counters    = Cs} = S) ->
    GRs1 = [apply_modifiers(Modifiers, G) || G <- GRs],
    Qs1  = [apply_modifiers(Modifiers, Q) || Q <- Qs],
    {Revisit,Cs1}  =
        lists:foldl(fun(C,{RevAcc,CAcc}) ->
                            C1 = apply_modifiers(Modifiers, C),
                            case get_rate(C) < get_rate(C1) of
                                true -> {union(C1#cr.queues,RevAcc),[C1|CAcc]};
                                _ -> {RevAcc,[C1|CAcc]}
                            end
                    end,{[],[]},Cs),
    S1 = revisit_queues(Revisit,
                        S#st{queues = Qs1,
                             group_rates = GRs1,
                             counters = lists:reverse(Cs1)}),
    {reply, ok, S1};
i_handle_call({add_queue, Name, Options}, _, #st{queues = Qs} = S) ->
    false = get_queue(Name, Qs),
    NewQueues = init_queues([{Name, Options}], S),
    revisit_queue(Name),
    {reply, ok, lift_counters(S#st{queues = Qs ++ NewQueues})};
i_handle_call({modify_queue, Name, Options}, _, #st{queues = Qs} = S) ->
    case get_queue(Name, Qs) of
	false ->
	    {reply, {error, not_found}, S};
	#queue{} = Q ->
	    Q1 = lists:foldl(
		   fun({max_size, Sz}, Qx) when is_integer(Sz), Sz >= 0;
						Sz==undefined ->
			   Qx#queue{max_size = Sz};
		      ({max_time, T}, Qx) when is_integer(T), T >= 0;
					       T==undefined ->
			   Qx#queue{max_time = T}
		   end, Q, Options),
	    revisit_queue(Name),
	    {reply, ok, update_queue(Q1, S)}
    end;
i_handle_call({delete_queue, Name}, _, #st{queues = Qs} = S) ->
    case get_queue(Name, Qs) of
        false ->
            {reply, false, S};
        #queue{} = Q ->
            %% for now, let's be very brutal
	    case Q of
		#queue{st = undefined} -> ok;
		_ ->
		    [reject(Client) || {_, Client} <- q_all(Q)]
	    end,
            q_delete(Q),
            {reply, true, S#st{queues = lists:keydelete(Name,#queue.name,Qs)}}
    end;
i_handle_call({info, Item}, _, S) ->
    {reply, get_info(Item, S), S};
i_handle_call({queue_info, Name}, _, #st{queues = Qs} = S) ->
    {reply, get_queue_info(Name, Qs), S};
i_handle_call({queue_info, Name, Item}, _, #st{queues = Qs} = S) ->
    {reply, get_queue_info(Name, Item, Qs), S};
i_handle_call({modify_regulator, Type, Qname, RegName, Opts}, _, S) ->
    case get_queue(Qname, S#st.queues) of
        #queue{} = Q ->
            case do_modify_regulator(Type, RegName, Opts, Q) of
                badarg ->
                    {reply, badarg, S};
                Q1 ->
                    S1 = update_queue(Q1, S),
                    {reply, ok, S1}
            end;
        _ ->
            {reply, badarg, S}
    end;
i_handle_call({modify_counter, CName, Opts}, _, #st{counters = Cs} = S) ->
    case get_counter(CName, Cs) of
        false ->
            {reply, badarg, S};
        #cr{} = CR ->
            try CR1 = init_counter(Opts, CR),
                {reply, ok, S#st{counters = update_counter(CName,Cs,CR1)}}
            catch
                error:_ ->
                    {reply, badarg, S}
            end
    end;
i_handle_call({delete_counter, Name}, _, #st{counters = Cs} = S) ->
    case get_counter(Name, Cs) of
	false ->
	    {reply, false, S};
	#cr{} ->
	    %% The question is whether we should also delete references
	    %% to the queue? It seems like we should...
	    Cs1 = lists:keydelete(Name, #cr.name, Cs),
	    {reply, true, S#st{counters = Cs1}}
    end;
i_handle_call({add_counter, Name, Opts}=Req, _, #st{counters = Cs} = S) ->
    case get_counter(Name, Cs) of
        false ->
            try CR = init_counter([{name,Name}|Opts], #cr{name = Name,
                                                          shared = true}),
		 CR1 = pickup_aliases(S#st.queues, CR),
		 {reply, ok, S#st{counters = Cs ++ [CR1]}}
            catch
                error:Reason ->
                    error_logger:error_report([{error, Reason},
                                               {request, Req}]),
                    {reply, badarg, S}
            end;
        _ ->
            {reply, badarg, S}
    end;
i_handle_call({add_group_rate, Name, Opts}=Req,_, #st{group_rates = Gs} = S) ->
    case get_group(Name, Gs) of
        false ->
            try GR = init_group(Opts, #grp{name = Name}),
                {reply, ok, S#st{group_rates = Gs ++ [GR]}}
            catch
                error:Reason ->
                    error_logger:error_report([{error, Reason},
                                               {request, Req}]),
                    {reply, badarg, S}
            end;
        _ ->
            {reply, badarg, S}
    end;
i_handle_call({modify_group_rate, Name, Opts},_, #st{group_rates = Gs} = S) ->
    case get_group(Name, Gs) of
        #grp{} = G ->
            try G1 = init_group(Opts, G),
                {reply, ok, S#st{group_rates = update_group(Name,Gs,G1)}}
            catch
                error:_ ->
                    {reply, badarg, S}
            end;
        _ ->
            {reply, badarg, S}
    end;
i_handle_call({ask_queue, QName, Req}, From, #st{queues = Qs} = S) ->
    case get_queue(QName, Qs) of
	false ->
	    {reply, badarg, S};
	#queue{stateful = Stf} = Q ->
	    SetQState =
		fun(Stf1) ->
			S#st{queues =
				 lists:keyreplace(QName, #queue.name, Qs,
						  Q#queue{stateful = Stf1})}
		end,
	    %% We don't catch errors; this is done at the level above.
	    %% One possible error is that the queue module doesn't have a
	    %% handle_call/3 callback.
	    case ask_stateful(Req, From, Stf, S#st.info_f) of
		badarg -> {reply, badarg, S};
		{reply, Reply, Stf1} ->
		    {reply, Reply, SetQState(Stf1)};
		{noreply, Stf1} ->
		    {noreply, SetQState(Stf1)}
	    %% case M:handle_call(Req, From, QSt) of
	    %% 	{reply, Rep, QSt1} ->
	    %% 	    {reply, Rep, SetQState(QSt1)};
	    %% 	{noreply, QSt1} ->
	    %% 	    {noreply, SetQState(QSt1)}
	    end
    end;
i_handle_call(_Req, _, S) ->
    {reply, badarg, S}.

handle_cast({done, Pid, {Ref, Opaque}}, #st{monitors = Mons} = S) ->
    Cs = proplists:get_value(counters, Opaque, []),
    case ets:lookup(Mons, {Pid,Ref}) of
	[] ->
	    %% huh?
	    io:fwrite("Didn't find monitor for Pid ~p~n", [Pid]);
	[_] ->
	    erlang:demonitor(Ref, [flush]),
	    ets:delete(Mons, {Pid,Ref})
    end,
    {Revisit, S1} = restore_counters(Cs, S),
    {noreply, revisit_queues(Revisit, S1)};
handle_cast(_Msg, S) ->
    {noreply, S}.

handle_info({'DOWN', Ref, _, Pid, _}, #st{monitors = Mons} = S) ->
    case ets:lookup(Mons, {Pid,Ref}) of
	[{_, QName}] ->
	    ets:delete(Mons, {Pid,Ref}),
	    Cs = get_counters(QName, S),  %% TODO! implement function
	    {Revisit, S1} = restore_counters(Cs, S),
	    {noreply, revisit_queues(Revisit, S1)};
	[] ->
	    {noreply, S}
    end;
handle_info({check_queue, Name}, #st{queues = Qs} = S) ->
    case get_queue(Name, Qs) of
        #queue{} = Q ->
            TS = timestamp(),
	    {Q1, S1} = perform_queue_check(Q#queue{timer = undefined}, TS, S),
	    {noreply, update_queue(restart_timer(Q1), S1)};
        _ ->
            {noreply, S}
    end;
handle_info(_Msg, S) ->
    io:fwrite("~p: handle_info(~p,~p)~n", [?MODULE, _Msg,S]),
    {noreply, S}.

terminate(_,_) ->
    ok.

code_change(_FromVsn, St, _Extra) ->
    {ok, set_info(St)}.


%% Internal functions

get_info(queues, #st{queues = Qs}) ->
    jobs_info:pp(Qs);
get_info(group_rates, #st{group_rates = Gs}) ->
    jobs_info:pp(Gs);
get_info(counters, #st{counters = Cs}) ->
    jobs_info:pp(Cs).

get_queue_info(Name, Qs) ->
    case get_queue(Name, Qs) of
        false ->
            undefined;
	Other ->
	    jobs_info:pp(Other)
    end.

get_queue_info(Name, Item, Qs) ->
    case get_queue(Name, Qs) of
	false ->
	    undefined;
	Q ->
	    do_get_queue_info(Item, Q)
    end.

do_get_queue_info(rate_limit, #queue{regulators = Rs}) ->
    case lists:keyfind(rr, 1, Rs) of
	#rr{rate = #rate{limit = Limit}} ->
	    Limit;
	false ->
	    undefined
    end;
do_get_queue_info(Item, Q) ->
    jobs_info:'#get-queue'(Item, Q).

get_queue(Name, Qs) ->
    lists:keyfind(Name, #queue.name, Qs).

get_group(undefined, _) ->
    false;
get_group(Name, Groups) ->
    lists:keyfind(Name, #grp.name, Groups).

get_counter(undefined, _) ->
    false;
get_counter(Name, Cs) ->
    lists:keyfind(Name, #cr.name, Cs).

update_group(Name, Gs, GR) ->
    lists:keyreplace(Name, #grp.name, Gs, GR).

update_counter(Name, Cs, CR) ->
    lists:keyreplace(Name, #cr.name, Cs, CR).

update_rate_regulator(RR, Rs) ->
    %% At most one rate regulator allowed per queue - match on record tag
    lists:keyreplace(rr, 1, Rs, RR).


do_modify_regulator(Type, Name, Opts, #queue{} = Q) ->
    case lists:keymember(name, 1, Opts) of
        true ->
            badarg;
        false ->
            ok
    end,
    case Type of
        rate    -> do_modify_rate_regulator(Name, Opts, Q);
        counter -> do_modify_counter_regulator(Name, Opts, Q);
        _ ->
            badarg
    end.

do_modify_rate_regulator(Name, Opts, #queue{regulators = Regs} = Q) ->
    case lists:keyfind(Name, #rr.name, Regs) of
        #rr{} = RR ->
            try RR1 = init_rate_regulator(Opts, RR),
                Q#queue{regulators = lists:keyreplace(
                                           Name,#rr.name,Regs,RR1)}
            catch
                error:_ ->
                    badarg
            end;
        _ ->
            badarg
    end.

do_modify_counter_regulator(Name, Opts, #queue{regulators = Regs} = Q) ->
    case lists:keyfind(Name, #rr.name, Regs) of
        #cr{} = CR ->
            try CR1 = init_counter(Opts, CR),
                Q#queue{regulators = lists:keyreplace(
				   Name,#cr.name,Regs,CR1)}
            catch
                error:_ ->
                    badarg
            end;
        _ ->
            badarg
    end.

job_queued(#queue{check_counter = Ctr} = Q, PrevSz, TS, S) ->
    case Ctr + 1 of
	C when C > 10 ->
	    perform_queue_check(Q, TS, S);
	C ->
	    Q1 = Q#queue{check_counter = C},
	    if PrevSz == 0 ->
		    perform_queue_check(Q1, TS, S);
	       true ->
		    {Q#queue{check_counter = C}, S}
	    end
    end.

check_timedout(#queue{max_time   = undefined} = Q, _) -> Q;
check_timedout(#queue{oldest_job = undefined} = Q, _) -> Q;
check_timedout(#queue{max_time   = MaxT,
		      oldest_job = Oldest} = Q, TS) ->
    if (TS - Oldest) > MaxT * 1000 ->
	    case q_timedout(Q) of
		{[],Q1} -> Q1;
		{OldJobs, Q1} ->
		    [timeout(J) || J <- OldJobs],
		    Q1
	    end;
       true ->
	    Q
    end.


perform_queue_check(Q, TS, S) ->
    Q1 = check_timedout(maybe_cancel_timer(Q), TS),
    case check_queue(Q1, TS, S) of
	{0, _, _} ->
	    {Q1, update_queue(Q1, S)};
	{N, Counters, Regs} when N > 0 ->
	    {Nd, _Jobs, Q2} = dispatch_N(N, Counters, TS, Q1, S),
	    {_Q3, _S3} = update_counters_and_regs(Nd, Counters, Regs, Q2, S);
	    %% {Q3, S3} = update_regulators(
	    %% 		 Regs, Q2#queue{latest_dispatch = TS,
	    %% 				check_counter = 0}, S),
	    %% update_counters(Jobs, Counters, update_queue(Q3, S3));
	Bad ->
	    erlang:error({bad_N, Bad})
    end.

maybe_cancel_timer(#queue{timer = undefined} = Q) ->
    Q;
maybe_cancel_timer(#queue{timer = TRef} = Q) ->
    erlang:cancel_timer(TRef),
    Q#queue{timer = undefined}.

check_queue(#queue{type = {action, approve}}, _TS, _S) ->
    {0, [], []};
check_queue(#queue{type = #producer{}} = Q, TS, S) ->
    do_check_queue(Q, TS, S);
check_queue(#queue{} = Q, TS, S) ->
    case q_is_empty(Q) of
        true ->
            %% no action necessary
            {0, [], []};
        false ->
            %% non-empty queue
	    do_check_queue(Q, TS, S)
    end.

do_check_queue(#queue{regulators = Regs0} = Q, TS, S) ->
    Regs = expand_regulators(Regs0, S),
    {N, Counters} = check_regulators(Regs, TS, Q),
    {N, Counters, Regs}.


-type exp_regulator() :: {#cr{}, integer() | undefined} | #rr{} | #grp{}.

-spec expand_regulators([regulator()], #st{}) -> [exp_regulator()].
%%
expand_regulators([#group_rate{name = R}|Regs], #st{group_rates = GRs} = S) ->
    case get_group(R, GRs) of
	false       -> expand_regulators(Regs, S);
	#grp{} = GR -> [GR|expand_regulators(Regs, S)]
    end;
expand_regulators([#counter{name = C,
			    increment = I}|Regs], #st{counters = Cs} = S) ->
    case get_counter(C, Cs) of
	false      -> expand_regulators(Regs, S);
	#cr{} = CR -> [{CR,I}|expand_regulators(Regs, S)]
    end;
expand_regulators([#rr{} = R|Regs], S) ->
    [R|expand_regulators(Regs, S)];
expand_regulators([#cr{} = R|Regs], S) ->
    [R|expand_regulators(Regs, S)];
expand_regulators([], _) ->
    [].

get_counters(QName, #st{queues = Qs} = S) ->
    case get_queue(QName, Qs) of
	false ->
	    [];
	#queue{regulators = Rs} ->
	    CRs = expand_regulators([C || #counter{} = C <- Rs], S),
	    [{C, cr_increment(Ig,Il)} ||
		{#cr{name = C, increment = Ig}, Il} <- CRs]
    end.

%% include_regulator(false, _, Regs, S) ->
%%     expand_regulators(Regs, S);
%% include_regulator(R, Local, Regs, S) ->
%%     [{R, Local}|expand_regulators(Regs, S)].

update_counters_and_regs(NJobs, Counters, Regs, Q, S) ->
    update_regulators(Regs, Q, update_counters(NJobs, Counters, S)).

update_regulators(Regs, Q0, S0) ->
    lists:foldl(
      fun(#grp{name = R} = GR, {Q, #st{group_rates = GRs} = S}) ->
	      GR1 = GR#grp{latest_dispatch = Q#queue.latest_dispatch},
              S1 = S#st{group_rates = update_group(R, GRs, GR1)},
              {Q, S1};
         (#rr{} = RR, {#queue{regulators = Rs} = Q, S}) ->
              %% There can be at most one rate regulator
              Q1 = Q#queue{regulators = update_rate_regulator(RR, Rs)},
              {Q1, S};
	 (_, Acc) ->
	      Acc
         %% (#cr{name = R,
         %%      shared = true} = CR, {Q, #st{counters = Cs} = S}) ->
         %%      S1 = S#st{counters = update_counter(R, Cs, CR)},
         %%      {Q, S1};
         %% (#cr{name = R} = CR, {#queue{regulators = Rs} = Q, S}) ->
         %%      Q1 = Q#queue{regulators = update_counter(R, Rs, CR)},
         %%      {Q1, S}
      end, {Q0, S0}, Regs).


-spec check_regulators([exp_regulator()], timestamp(), #queue{}) ->
			      {integer(), [any()]}.
%%
check_regulators(Regs, TS, #queue{latest_dispatch = TL}) ->
    case check_regulators(Regs, TS, TL, undefined, []) of
	{undefined, _} ->
	    {0, []};
	Other ->
	    Other
    end.

check_regulators([R|Regs], TS, TL, N, Cs) ->
    case R of
	#rr{rate = #rate{interval = I}} ->
	    N1 = check_rr(I, TS, TL),
	    check_regulators(Regs, TS, TL, erlang:min(N, N1), Cs);
	#grp{rate = #rate{interval = I}, latest_dispatch = TLg} ->
	    N1 = check_rr(I, TS, TLg),
	    check_regulators(Regs, TS, TL, erlang:min(N, N1), Cs);
	{#cr{} = CR, Il} ->
	    #cr{name = Name,
		value = Val,
		increment = Ig,
		rate = #rate{limit = Max}} = CR,
	    I = cr_increment(Ig, Il),
	    C1 = check_cr(Val, I, Max),
	    Cs1 = if C1 == 0 ->
			  Cs;
		     true ->
			  [{Name, I}|Cs]
		  end,
	    check_regulators(Regs, TS, TL, erlang:min(C1, N), Cs1)
    end;
check_regulators([], _, _, N, Cs) ->
    {N, Cs}.

cr_increment(Ig, undefined) -> Ig;
cr_increment(_ , Il) when is_integer(Il) -> Il.

check_rr(undefined, _, _) ->
    0;
check_rr(I, _, 0) ->
    %% initial dispatch
    if I > 0 ->
	    1;
       true ->
	    0
    end;
check_rr(I, TS, TL) when TS > TL, I > 0 ->
    trunc((TS - TL)/(I*1000)).

check_cr(Val, I, Max) ->
    case Max - Val of
	N when N > 0 ->
	    N div I;
	_ ->
	    0
    end.

-spec dispatch_N(integer() | infinity, [any()], integer(), #queue{}, #st{}) ->
			{list(), #queue{}}.
%%
dispatch_N(N, Counters, TS, #queue{name = QName,
				    approved = Approved0,
				    type = #producer{mod = Mod,
						     state = MS} = Prod} = Q,
	   #st{monitors = Mons, info_f = I}) ->
    {Jobs, MS1} = spawn_producers(N, Mod, MS, Counters, I),
    monitor_jobs(Jobs, QName, Mons),
    Prod1 = Prod#producer{state = MS1},
    %% Jobs = [spawn_mon_producer(F) || _ <- lists:seq(1,N)],
    %% lists:foreach(
    %%   fun({Pid,Ref}) ->
    %% 	      ets:insert(Mons, {{Pid,Ref}, QName})
    %%   end, Jobs),
    %% {Jobs, Q};
    {N, Jobs, Q#queue{type = Prod1, approved = Approved0 + N,
		      latest_dispatch = TS}};
dispatch_N(N, Counters, TS, Q, #st{} = S) ->
    {Jobs, Q1} = q_out(N, Q),
    dispatch_jobs(Jobs, Counters, TS, Q1, S).

dispatch_jobs(Jobs, [], TS, #queue{name = QName, stateful = Stf0} = Q,
	      #st{info_f = I, monitors = Mons}) ->
    {Nd, NStf} = lists:foldl(
		   fun({_,{Pid,Ref}} = Job, {N, Stf}) ->
			   ets:insert(Mons, {{Pid,Ref}, QName}),
			   {_, Client, Opaque, Stf1} =
			       job_opaque(Job, [], Stf, I),
			   approve(Client, {Ref, Opaque}),
			   {N+1, Stf1}
		   end, {0, Stf0}, Jobs),
    Approved0 = Q#queue.approved,
    {Nd, Jobs, Q#queue{latest_dispatch = TS,
		       stateful = NStf,
		       approved = Approved0 + Nd}};
dispatch_jobs(Jobs, Counters, TS, #queue{stateful = Stf0} = Q,
	      #st{monitors = Mons, info_f = I}) ->
    Opaque0 = [{counters, Counters}],
    {Nd, NStf} = lists:foldl(
		   fun(Job, {N, Stf}) ->
			   {Pid, Client, Opaque, Stf1} =
			       job_opaque(Job, Opaque0, Stf, I),
			   Ref = erlang:monitor(process, Pid),
			   approve(Client, {Ref, Opaque}),
			   ets:insert(Mons, {{Pid, Ref}, Q#queue.name}),
			   {N+1, Stf1}
		   end, {0, Stf0}, Jobs),
    Approved0 = Q#queue.approved,
    {Nd, Jobs, Q#queue{latest_dispatch = TS,
		       stateful = NStf,
		       approved = Approved0 + Nd}}.

update_stateful(undefined, _, _) ->
    undefined;
update_stateful({Mod, ModS}, Opaque, I) ->
    {V, S1} = Mod:next(Opaque, ModS, I),
    {V, {Mod, S1}}.

ask_stateful(_Req, _, undefined, _) ->
    badarg;
ask_stateful(Req, From, {Mod, ModS}, I) ->
    case Mod:handle_call(Req, From, ModS, I) of
	{reply, Reply, NewModS} ->
	    {reply, Reply, {Mod, NewModS}};
	{noreply, NewModS} ->
	    {noreply, {Mod, NewModS}}
    end.


spawn_producers(N, Mod, ModS, Counters, I) ->
    spawn_producers(N, Mod, ModS, [{counters, Counters}], I, []).

spawn_producers(N, Mod, ModS, Opaque, I, Acc) when N > 0 ->
    {F, ModS1} = Mod:next(Opaque, ModS, I),
    spawn_producers(N-1, Mod, ModS1, Opaque, I,
                    [spawn_monitor(F) | Acc]);
spawn_producers(_, _, ModS, _, _, Acc) ->
    {Acc, ModS}.

monitor_jobs(Jobs, QName, Mons) ->
    lists:foreach(
      fun({Pid,Ref}) ->
              ets:insert(Mons, {{Pid,Ref}, QName})
      end, Jobs).

%% spawn_mon_producer({M, F, A}) ->
%%     spawn_monitor(M, F, A);
%% spawn_mon_producer(F) when is_function(F, 0) ->
%%     spawn_monitor(F).


job_opaque({_, {Pid,_} = Client}, Opaque, Stf, I) ->
    Stf1 = update_stateful(Stf, Opaque, I),
    {Pid, Client, add_stateful(Stf1, Opaque), stateful_st(Stf1)}.
%% job_opaque({_, {Pid,_} = Client, Info}, Opaque, Stf, I) ->
%%     Opaque1 = [{info, Info}|Opaque],
%%     Stf1 = update_stateful(Stf, Opaque1, I),
%%     {Pid, Client, add_stateful(Stf1, Opaque1), stateful_st(Stf1)}.

add_stateful(undefined, Opaque) ->
    Opaque;
add_stateful({V, _}, Opaque) ->
    [{info, V}|Opaque].

stateful_st(undefined) -> undefined;
stateful_st({_, St}) -> St.


update_counters(_, [], S) -> S;
update_counters(N, Cs, #st{counters = Counters} = S) ->
    Counters1 =
	lists:foldl(
	  fun({C,I}, Acc) ->
		  #cr{value = Old} = CR =
		      lists:keyfind(C, #cr.name, Acc),
		  CR1 = CR#cr{value = Old + I*N},
		  lists:keyreplace(C, #cr.name, Acc, CR1)
	  end, Counters, Cs),
    S#st{counters = Counters1}.


restore_counters(Cs, #st{} = S) ->
    lists:foldl(fun restore_counter/2, {[], S}, Cs).

restore_counter({C, I}, {Revisit, #st{counters = Counters} = S}) ->
    #cr{value = Val, queues = Qs} = CR =
	lists:keyfind(C, #cr.name, Counters),
    CR1 = CR#cr{value = Val - I},
    Counters1 = lists:keyreplace(C, #cr.name, Counters, CR1),
    S1 = S#st{counters = Counters1},
    {union(Qs, Revisit), S1}.

union(L1, L2) ->
    (L1 -- L2) ++ L2.

revisit_queues(Qs, S) ->
    Expanded = [{Q, get_latest_dispatch(Q, S)} || Q <- Qs],
    [revisit_queue(Q) || {Q,_} <- lists:keysort(2, Expanded)],
    S.

get_latest_dispatch(Q, #st{queues = Qs}) ->
    #queue{latest_dispatch = Tl} =
	lists:keyfind(Q, #queue.name, Qs),
    Tl.

revisit_queue(Qname) ->
    self() ! {check_queue, Qname}.

update_queue(#queue{name = N, type = T} = Q, #st{queues = Qs} = S) ->
    Q1 = case T of
	     {passive, _} -> Q;
	     _ ->
		 start_timer(Q)
	 end,
    S#st{queues = lists:keyreplace(N, #queue.name, Qs, Q1)}.

kick_producers(#st{queues = Qs} = S) ->
    lists:foreach(
      fun(#queue{name = Qname, type = #producer{}}) ->
	      revisit_queue(Qname);
	 (_Q) ->
	      ok
      end, Qs),
    S.

restart_timer(Q) ->
    start_timer(maybe_cancel_timer(Q)).

start_timer(#queue{timer = TRef} = Q) when TRef =/= undefined ->
    Q;
start_timer(#queue{name = Name} = Q) ->
    case next_time(timestamp(), Q) of
        T when is_integer(T) ->
            Msg = {check_queue, Name},
            TRef = do_send_after(T, Msg),
            Q#queue{timer = TRef};
        undefined ->
            Q
    end.

do_send_after(T, Msg) when T > 0 ->
    erlang:send_after(T, self(), Msg);
do_send_after(_, Msg) ->
    self() ! Msg,
    undefined.

apply_modifiers(Modifiers, #queue{regulators = Rs} = Q) ->
    Rs1 = [apply_modifiers(Modifiers, R) || R <- Rs],
    Q#queue{regulators = Rs1};
apply_modifiers(_, #counter{} = C) ->
    %% this is just an alias to a counter; modifiers are applied to counters separately
    C;
apply_modifiers(Modifiers, Regulator) ->
    with_modifiers(Modifiers, Regulator, fun apply_damper/4).

%% (Don't quite remember right now when this is supposed to be used...)
%%
%% remove_modifiers(Modifiers, Regulator) ->
%%     with_modifiers(Modifiers, Regulator, fun remove_damper/4).

%% remove_damper(Type, _, _, R) ->
%%     apply_corr(Type, 0, R).


with_modifiers(Modifiers, Regulator, F) ->
    Rate = get_rate(Regulator),
    R0 = lists:foldl(
	   fun({K, Local, Remote}, R) ->
		   F(K, Local, Remote, R)
	   end, Rate, Modifiers),
    R1 = apply_active_modifiers(R0),
    set_rate(R1, Regulator).


apply_damper(Type, Local, Remote, R) ->
    case lists:keyfind(Type, 1, R#rate.modifiers) of
	false ->
	    %% no effect on this regulator
	    R;
	Found ->
	    apply_damper(Type, Found, Local, Remote, R)
    end.

apply_damper(Type, _Found, 0, [], R) ->
    apply_corr(Type, 0, R);
apply_damper(Type, Found, Local, Remote, R) ->
    case Found of
	{_, Unit} when is_integer(Unit) ->
            %% The active_modifiers list is kept up-to-date in order
            %% to support remove_damper().
            Corr = Local * Unit,
	    apply_corr(Type, Corr, R);
	{_, LocalUnit, RemoteUnit} ->
	    LocalCorr = Local * LocalUnit,
	    RemoteCorr = case RemoteUnit of
			     {avg, RU} ->
				 RU * avg_remotes(Remote);
			     {max, RU} ->
				 RU * max_remotes(Remote)
			 end,
	    apply_corr(Type, LocalCorr + RemoteCorr, R);
	{_, {M,F}} ->
	    case M:F(Local, Remote) of
		Corr when is_integer(Corr) ->
		    apply_corr(Type, Corr, R)
	    end;
	{_, F} when is_function(F,2) ->
	    case F(Local, Remote) of
		Corr when is_integer(Corr) ->
		    apply_corr(Type, Corr, R)
	    end
    end.

avg_remotes([]) ->
    0;
avg_remotes(L) ->
    Sum = lists:foldl(fun({_,V}, Acc) -> V + Acc end, 0, L),
    Sum div length(L).

max_remotes(L) ->
    lists:foldl(fun({_,V}, Acc) ->
			erlang:max(V, Acc)
		end, 0, L).

apply_corr(Type, 0, R) ->
    R#rate{active_modifiers = lists:keydelete(
                                Type, 1, R#rate.active_modifiers)};
apply_corr(Type, Corr, R) ->
    ADs = lists:keystore(Type, 1, R#rate.active_modifiers,
			 {Type, Corr}),
    R#rate{active_modifiers = ADs}.



get_rate(#rr {rate = R}) -> R;
get_rate(#cr {rate = R}) -> R;
get_rate({#cr {rate = R},_}) -> R;
get_rate(#grp{rate = R}) -> R.

set_rate(R, #rr {} = Reg) -> Reg#rr {rate = R};
set_rate(R, #cr {} = Reg) -> Reg#cr {rate = R};
set_rate(R, #grp{} = Reg) -> Reg#grp{rate = R}.


apply_active_modifiers(#rate{preset_limit = Preset,
			     active_modifiers = ADs} = R) ->
    Limit = lists:foldl(
	      fun({_,Corr}, L) ->
		      L - round(Corr*Preset/100)
	      end, Preset, ADs),
    R#rate{limit = Limit,
	   interval = interval(Limit)}.

queue_job(TS, From, #queue{max_size = MaxSz} = Q, S) ->
    CurSz = q_info(length, Q),
    if CurSz >= MaxSz ->
            case q_timedout(Q) of
                {[],Q1} ->
                    reject(From),
                    {Q1, S};
                {OldJobs, Q1} ->
                    [timeout(J) || J <- OldJobs],
                    %% update_queue(q_in(TS, From, Q1), S)
                    job_queued(q_in(TS, From, Q1), CurSz, TS, S)
            end;
       true ->
            %% update_queue(q_in(TS, From, Q), S)
            job_queued(q_in(TS, From, Q), CurSz, TS, S)
    end.

do_enqueue(TS, Item, #queue{max_size = MaxSz} = Q, S) ->
    CurSz = q_info(length, Q),
    if CurSz >= MaxSz ->
	    {{error, full}, S};
       true ->
	    {ok, update_queue(q_in(TS, Item, Q), S)}
    end.

select_queue(Type, _, #st{q_select = undefined, default_queue = Def} = S) ->
    if Type == undefined ->
            {Def, S};
       true ->
            {Type, S}
    end;
select_queue(Type, _, #st{q_select = M, q_select_st = MS, info_f = I} = S) ->
    case M:queue_name(Type, MS, I) of
        {ok, Name, MS1} ->
            {Name, S#st{q_select_st = MS1}};
        {error, Reason} ->
            erlang:error({badarg, Reason})
    end.


%% ===========================================================
%% Queue accessor functions.
%% It is possible to define a different queue type through the option
%% queue_mod :: atom()  (Default = jobs_queue)
%% The callback module must implement the functions below.
%%
q_new(Opts) ->
    [Name, Mod, Type, Stateful, MaxTime, MaxSize] =
        [get_value(K, Opts, Def) || {K, Def} <- [{name, undefined},
                                                 {mod , jobs_queue},
						 {type, fifo},
						 {stateful, undefined},
                                                 {max_time, undefined},
                                                 {max_size, undefined}]],
    Q0 = #queue{name = Name,
		mod = Mod,
		type = Type,
		max_time = MaxTime,
		max_size = MaxSize},
    Q1 = Q0#queue{stateful = init_stateful(Stateful, Q0)},
    case Type of
	{producer, F} ->
	    init_producer(F, Opts, Q1);
	    %% Q0#queue{type = #producer{f    = F}};
	{action  , A} -> Q1#queue{type = #action  {a    = A}};
	_ ->
	    #queue{} = q_new(Opts, Q1, Mod)
    end.

q_new(Options, Q, Mod) ->
    Mod:new(queue_options(Options, Q), Q).

queue_options(Opts, #queue{type = #passive{type = T}}) ->
    [{type, T}|Opts];
queue_options(Opts, _) ->
    Opts.

init_stateful(undefined, _) ->
    undefined;
init_stateful(F, Q) ->
    {Mod, Args} = init_f(F, jobs_stateful_simple),
    ModS = Mod:init(Args, jobs_info:pp(Q)),
    {Mod, ModS}.

init_f(Type, DefMod) ->
    case Type of
	F when is_function(F, 0); is_function(F, 2) ->
	    {DefMod, F};
	{M,F,A} ->
	    {DefMod, {M,F,A}};
	{M, A} when is_atom(M) ->
	    {M, A}
    end.

init_producer(Type, _Opts, Q) ->
    {Mod, Args} = init_f(Type, jobs_prod_simple),
    ModS = Mod:init(Args, jobs_info:pp(Q)),
    Q#queue{type = #producer{mod = Mod,
                             state = ModS}}.

q_all     (#queue{mod = Mod} = Q)     -> Mod:all     (Q).
q_timedout(#queue{mod = Mod} = Q)     -> case Mod:timedout(Q) of [] -> {[],Q}; X -> X end.
q_delete  (#queue{mod = undefined})   -> ok;
q_delete  (#queue{mod = Mod} = Q)     -> Mod:delete  (Q).
%%
%q_is_empty(#queue{type = #producer{}}) -> false;
q_is_empty(#queue{mod = Mod} = Q)       -> Mod:is_empty(Q).
%%
q_out     (infinity, #queue{mod = Mod} = Q) -> Mod:all  (Q);
q_out     (N , #queue{mod = Mod} = Q) -> Mod:out     (N, Q).
q_info    (I , #queue{mod = Mod} = Q) -> Mod:info    (I, Q).
%%
q_in(TS, From, #queue{mod = Mod, oldest_job = OJ} = Q) ->
    OJ1 = erlang:min(TS, OJ),    % Works even if OJ==undefined
    Mod:in(TS, From, Q#queue{oldest_job = OJ1}).

%% End queue accessor functions.
%% ===========================================================

-spec next_time(TS :: integer(), #queue{}) -> integer() | undefined.
%%
%% Calculate the delay (in ms) until queue is checked again.
%%
next_time(TS, #queue{type = #producer{}} = Q) ->
    next_time_(TS, Q);
next_time(_, #queue{type = #passive{}}) -> undefined;
next_time(_TS, #queue{oldest_job = undefined}) ->
    %% queue is empty
    undefined;
next_time(TS, Q) ->
    next_time_(TS, Q).
%% next_time(TS, #queue{check_interval = infinity,
%% 		      max_time = MaxT,
%% 		      oldest_job = Oldest}) ->
%%     case MaxT of
%% 	undefined -> undefined;
%% 	_ ->
%% 	    %% timestamps are us, timeouts need to be in ms
%% 	    erlang:max(0, MaxT - ((TS - Oldest) div 1000))
%%     end;
next_time_(TS, #queue{latest_dispatch = TS1,
		      check_interval = I0,
		      max_time = MaxT,
		      oldest_job = Oldest}) ->
    I = case I0 of
	    _ when is_number(I0) -> I0;
	    infinity -> undefined;
	    {M, F, As} ->
		M:F(TS, TS1, As)
	end,
    TO = case MaxT of
	     undefined -> undefined;
	     _ when is_integer(MaxT) ->
		 MaxT - ((TS - Oldest) div 1000)
	 end,
    NextI = if is_number(I) ->
		    Since = (TS - TS1) div 1000,
		    erlang:max(0, trunc(I - Since));
	       true ->
		    undefined
	    end,
    case {TO, NextI} of
	{undefined,undefined} -> undefined;
	{undefined,_} -> NextI;
	{_,undefined} -> TO;
	{_,_} -> erlang:min(TO, NextI)
    end.


%% Microsecond timestamp; never wraps
timestamp() ->
    %% Invented epoc is {1258,0,0}, or 2009-11-12, 4:26:40
    {MS,S,US} = erlang:now(),
    (MS-1258)*1000000000000 + S*1000000 + US.

timestamp_to_datetime(TS) ->
    %% Our internal timestamps are relative to Now = {1258,0,0}
    %% It doesn't really matter much how we construct a now()-like tuple,
    %% as long as the weighted sum of the three numbers is correct.
    S = TS div 1000000,
    MS = round(TS rem 1000000 / 1000),
    %% return {Datetime, Milliseconds}
    {calendar:now_to_datetime({1258,S,0}), MS}.


%% Enforce a maximum frequency of error reports
error_report(E) ->
    T = timestamp(),
    Key = {?MODULE, prev_error},
    case get(Key) of
        T1 when T - T1 > ?MAX_ERROR_RPT_INTERVAL_US ->
            error_logger:error_report(E),
            put(Key, T);
        _ ->
            ignore
    end.

%% get_value(K, [{_, _, Opts}|T], Default) ->
%%     case lists:keyfind(K, 1, Opts) of
%% 	false ->
%% 	    get_value(

get_all_values(K, Opts, Default) ->
    case get_all_values(K, Opts) of
	[] ->
	    Default;
	Other ->
	    Other
    end.

get_all_values(K, [{_, _, Opts}|T]) ->
    proplists:get_value(K, Opts, []) ++ get_all_values(K, T);
get_all_values(K, [{K, V}|T]) ->
    %% shouldn't happen - right, dialyzer?
    [V | get_all_values(K, T)];
get_all_values(_, []) ->
    [].

get_first_value(K, [{_,_,Opts}|T], Default) ->
    case lists:keyfind(K, 1, Opts) of
	false ->
	    get_first_value(K, T, Default);
	{_, V} ->
	    V
    end;
get_first_value(K, [{K, V}|_], _) ->
    %% Again, shouldn't happen
    V;
get_first_value(_, [], Default) ->
    Default.
