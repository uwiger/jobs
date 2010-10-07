%%==============================================================================
%% Copyright 2010 Erlang Solutions Ltd.
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
%% @author  : Ulf Wiger <ulf.wiger@erlang-solutions.com>
%% @end
%% Description : 
%%
%% Created : 15 Jan 2010 by Ulf Wiger <ulf.wiger@erlang-solutions.com>
%%-------------------------------------------------------------------
-module(jobs_server).
-behaviour(gen_server).

-export([ask/0,
         ask/1,
         run/1, run/2,
         done/1]).

-export([set_modifiers/1]).

%% Config API
-export([add_queue/2,
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


-compile(export_all).

-import(proplists, [get_value/3]).

-include("jobs.hrl").
-record(st, {queues      = []  :: [#queue{}],
	     group_rates = []  :: [#grp{}],
	     counters    = []  :: [#cr{}], 
	     monitors,
	     q_select          :: atom(),
	     q_select_st       :: any(),
	     default_queue,
	     interval    = 50  :: integer(),
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
    call(?SERVER, {ask, Type, timestamp()}, infinity).

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
    end.

-spec done(reg_obj()) -> ok.
%%
done(Opaque) ->
    gen_server:cast(?MODULE, {done, Opaque}).

-spec add_queue(queue_name(), [option()]) -> ok.
%%		       
add_queue(Name, Options) ->
    call(?SERVER, {add_queue, Name, Options}).

-spec delete_queue(queue_name()) -> ok.
delete_queue(Name) ->
    call(?SERVER, {delete_queue, Name}).

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

timeout(From) ->
    gen_server:reply(From, {error, timeout}).


%% start function

-spec start_link() -> {ok, pid()}.
%%
start_link() ->
    Opts = application:get_all_env(jobs),
    start_link(Opts).

-spec start_link([option()]) -> {ok, pid()}.
%%
start_link(Opts) when is_list(Opts) ->
    gen_server:start_link({local,?MODULE}, ?MODULE, Opts, []).

%% Server-side callbacks and helpers

-spec standard_modifiers() -> [q_modifier()].
%%
standard_modifiers() ->
    [{cpu, 10},
     {memory, 10}].

-spec init([option()]) -> {ok, #st{}}.
%%
init(Opts) ->
    process_flag(priority,high),
    S0 = #st{},
    [Qs, Gs, Cs, Interval] =
	[get_value(K,Opts,Def) 
	 || {K,Def} <- [{queues     , [{default,[]}]},
			{group_rates, []},
			{counters   , []},
			{interval   , S0#st.interval}]],
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
    Default = get_value(default_queue, Opts, Default0),
    {ok, set_info(lift_counters(S1#st{queues        = Queues,
				      default_queue = Default,
				      interval      = Interval,
				      monitors = ets:new(monitors,[set])}))}.



init_queues(Qs, S) ->
    lists:map(fun(Q) -> init_queue(Q,S) end, Qs).

init_queue({Name, standard_rate, R}, S) when is_integer(R), R > 0 ->
    init_queue({Name, [{regulators,
                        [{rate,
                          [{limit, R},
                           {modifiers, standard_modifiers()}]
                         }]
                       }]}, S);
init_queue({Name, standard_counter, N}, S) when is_integer(N), N > 0 ->
    init_queue({Name, [{regulators,
                        [{counter,
                          [{limit, N},
                           {modifiers, standard_modifiers()}]
                         }]
                       }]}, S);
init_queue({Name, producer, F, Opts}, S) ->
    init_queue({Name, [{type, {producer, F}} | Opts]}, S);
init_queue({Name, Opts}, S) ->
    [ChkI, Regs] =
        [get_value(K,Opts,D) ||
            {K, D} <- [{check_interval,undefined},
                       {regulators, []}]],
    Q0 = q_new([{name,Name}|Opts]),
    Q1 = init_regulators(Regs, Q0#queue{check_interval = ChkI}),
    calculate_check_interval(Q1, S).

calculate_check_interval(#queue{regulators = Rs,
                            check_interval = undefined} = Q, S) ->
    Regs = expand_regulators(Rs, S),
    I = lists:foldl(
          fun(R, Acc) ->
		  Rate = get_rate(R),
		  I1 = Rate#rate.interval div 1000,
                  erlang:min(I1, Acc)
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
			{init_counter(Opts, #cr{name = Name}), {Rx,Cx+1}};
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


init_counter(Opts) ->
    init_counter(Opts, #cr{}).

init_counter(Opts, #cr{} = CR0) ->
    R = #rate{},
    Limit = get_value(limit, Opts, R#rate.limit),
    Interval = get_value(interval, Opts, ?COUNTER_SAMPLE_INTERVAL),
    Modifiers = get_value(modifiers, Opts, R#rate.modifiers),
    CR0#cr{rate = #rate{limit = Limit,
			interval = Interval,
			preset_limit = Limit,
			modifiers = Modifiers}}.

lift_counters(#st{queues = Qs} = S) ->
    lists:foldl(fun do_lift_counters/2, S, Qs).

do_lift_counters(#queue{name = Name, regulators = Rs} = Q,
		 #st{queues = Queues, counters = Counters} = S) ->
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

mk_counter_alias(#cr{name = Name,
		     increment = I} = CR, {Rs, Cs}, QName) ->
    Alias = #counter{name = Name, increment = I},
    Rs1 = lists_replace(CR, Rs, Alias),
    case lists:keyfind(Name, #cr.name, Cs) of
	false ->
	    {Rs1, [CR#cr{queues = [QName]}|Cs]};
	#cr{} = Existing ->
	    Qs = [QName|Existing#cr.queues -- [QName]],
	    {Rs1, lists:keyreplace(Name, #cr.name, Cs,
				   Existing#cr{queues = Qs})}
    end.

lists_replace(X, [X | T], With) -> [With | T];
lists_replace(X, [A | T], With) -> [A | lists_replace(X, T, With)].


-spec interval(integer()) -> undefined | integer().
%%
%% Return the sampling interval (in ms) based on max frequency.
%% If max frequency is 0, we choose what corresponds to an unlimited interval
%%
interval(0    ) -> undefined;  % greater than any int()
interval(Limit) -> 1000 div Limit.


set_info(S) ->
    S#st{info_f = fun(Q) ->
                          %% We need to clear the info_f attribute, to 
                          %% avoid recursively inheriting all previous states.
                          get_info(Q, S#st{info_f = undefined})
                  end}.


%% Gen_server callbacks
handle_call(Req, From, S) ->
    try i_handle_call(Req, From, S) of
        {noreply, S1} ->
            {noreply, set_info(S1)};
        {reply, R, S1} ->
            {reply, R, set_info(S1)}
    catch
        error:Reason ->
            error_report([{error, Reason},
                          {request, Req}]),
            {reply, badarg, S}
    end.

i_handle_call({ask, Type, TS}, From, #st{queues = Qs} = S) ->
    {Qname, S1} = select_queue(Type, TS, S),
    case get_queue(Qname, Qs) of
        #action{type = Type} ->
            case Type of
                approve -> approve(From, []);
                reject  -> reject(From)
            end,
            {noreply, S1};
        #queue{} = Q ->
            {noreply, queue_job(TS, From, Q, S1)};
        false ->
            {reply, badarg, S1}
    end;
i_handle_call({set_modifiers, Modifiers}, _, #st{queues     = Qs,
						 group_rates = GRs,
						 counters    = Cs} = S) ->
    %% io:fwrite("~p: set_modifiers (~p)~n", [?MODULE, Modifiers]),
    GRs1 = [apply_modifiers(Modifiers, G) || G <- GRs],
    Cs1  = [apply_modifiers(Modifiers, C) || C <- Cs],
    Qs1  = [apply_modifiers(Modifiers, Q) || Q <- Qs],
    {reply, ok, S#st{queues = Qs1,
		     group_rates = GRs1,
		     counters = Cs1}};
i_handle_call({add_queue, Name, Options}, _, #st{queues = Qs} = S) ->
    false = get_queue(Name, Qs),
    NewQueues = init_queues([{Name, Options}], S),
    {reply, ok, S#st{queues = Qs ++ NewQueues}};
i_handle_call({delete_queue, Name}, _, #st{queues = Qs} = S) ->
    case get_queue(Name, Qs) of
        false ->
            {reply, false, S};
        #action{} = A ->
            {reply, true, S#st{queues = Qs -- [A]}};
        #queue{} = Q ->
            %% for now, let's be very brutal
            [reject(Client) || {_, Client} <- q_all(Q)],
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
i_handle_call({add_counter, Name, Opts}=Req, _, #st{counters = Cs} = S) ->
    case get_counter(Name, Cs) of
        false ->
            try CR = init_counter([{name,Name}|Opts], #cr{name = Name,
                                                          shared = true}),
                {reply, ok, S#st{counters = Cs ++ [CR]}}
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
i_handle_call(_Req, _, S) ->
    {reply, badarg, S}.

handle_cast({done, Pid, {Ref,Cs}}, #st{monitors = Mons} = S) ->
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
            Q1 = Q#queue{timer = undefined},
            case check_queue(Q1, TS, S) of
                {0, _, _} ->
                    {noreply, update_queue(Q1, S)};
                {N, Counters, Regs} ->
                    {Jobs, Q2} = dispatch_N(N, Counters, Q1, S),
		    
                    {Q3, S3} = update_regulators(
				 Regs, Q2#queue{latest_dispatch = TS}, S),
                    {noreply, update_counters(Jobs, Counters, 
					      update_queue(Q3, S3))}
            end;
        _ ->
            {noreply, S}
    end;
handle_info(_Msg, S) ->
    io:fwrite("~p: handle_info(~p,_)~n", [?MODULE, _Msg]),
    {noreply, S}.

terminate(_,_) ->
    ok.

code_change(_FromVsn, St, _Extra) ->
    {ok, St}.


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
    end.

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

check_queue(#queue{regulators = Regs0} = Q, TS, S) ->
    case q_is_empty(Q) of
        true ->
            %% no action necessary
            {0, [], []};
        false ->
            %% non-empty queue
            Regs = expand_regulators(Regs0, S),
            {N, Counters} = check_regulators(Regs, TS, Q),
            {N, Counters, Regs}
    end.



expand_regulators([{group_rate, R}|Regs], #st{group_rates = GRs} = S) ->
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

include_regulator(false, _, Regs, S) ->
    expand_regulators(Regs, S);
include_regulator(R, Local, Regs, S) ->
    [{R, Local}|expand_regulators(Regs, S)].


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


-spec check_regulators([regulator()], timestamp(), #queue{}) ->
			      {integer(), [any()]}.
%%
check_regulators(Regs, TS, #queue{latest_dispatch = TL}) ->
    check_regulators(Regs, TS, TL, infinity, []).

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
check_rr(I, TS, TL) ->
    trunc((TS - TL)/(I*1000)).

check_cr(Val, I, Max) ->
    case Max - Val of
	N when N > 0 ->
	    N div I;
	_ ->
	    0
    end.

-spec dispatch_N(integer() | infinity, [any()], #queue{}, #st{}) -> #queue{}.
%%			
dispatch_N(N, Counters, Q, #st{monitors = Mons}) ->
    {Jobs, _Q1} = Res = q_out(N, Q),
    lists:foreach(
      fun({_, {Pid,_} = Client}) ->
	      Ref = erlang:monitor(process, Pid),
	      approve(Client, {Ref, Counters}),
	      ets:insert(Mons, {{Pid,Ref}, Q#queue.name})
      end, Jobs),
    %% [approve(Client, Counters) || {_, Client} <- Jobs],
    Res.

update_counters(Jobs, Cs, 
		#st{counters = Counters} = S) ->
    N = length(Jobs),
    %% Clients = [{{Pid, erlang:monitor(process, Pid)}, QName} ||
    %% 		  {_, {Pid,_}} <- Jobs],
    %% ets:insert(Mons, Clients),
    Counters1 =
	lists:foldl(
	  fun({C,I}, Acc) ->
		  #cr{value = Old} = CR =
		      lists:keyfind(C, #cr.name, Acc),
		  %% io:fwrite("updating #cr{name = ~p}; Old=~p, I=~p, N=~p~n",
		  %% 	    [C,Old,I,N]),
		  CR1 = CR#cr{value = Old + I*N},
		  lists:keyreplace(C, #cr.name, Acc, CR1)
	  end, Counters, Cs),
    S#st{counters = Counters1}.


restore_counters(Cs, #st{} = S) ->
    lists:foldl(fun restore_counter/2, {[], S}, Cs).

restore_counter({C, I}, {Revisit, #st{counters = Counters} = S}) ->
    #cr{value = Val, queues = Qs, rate = #rate{limit = Max}} = CR =
	lists:keyfind(C, #cr.name, Counters),
    CR1 = CR#cr{value = Val - I},
    Counters1 = lists:keyreplace(C, #cr.name, Counters, CR1),
    S1 = S#st{counters = Counters1},
    if Val == Max, I > 0 ->
	    {union(Qs, Revisit), S1};
       true ->
	    {Revisit, S1}
    end.

union(L1, L2) ->
    (L1 -- L2) ++ L2.

revisit_queues(Qs, S) ->	     
    [self() ! {check_queue, Q} || Q <- Qs],
    S.
      

update_queue(#queue{name = N} = Q, #st{queues = Qs} = S) ->
    Q1 = start_timer(Q),
    S#st{queues = lists:keyreplace(N, #queue.name, Qs, Q1)}.

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

next_time(TS, TSl, I) ->
    Since = (TS - TSl) div 1000,
    erlang:max(0, I - Since).

do_send_after(T, Msg) ->
    erlang:send_after(T, self(), Msg).

apply_modifiers(Modifiers, #queue{regulators = Rs} = Q) ->
    Rs1 = [apply_modifiers(Modifiers, R) || R <- Rs],
    Q#queue{regulators = Rs1};
apply_modifiers(Modifiers, Regulator) ->
    with_modifiers(Modifiers, Regulator, fun apply_damper/4).

remove_modifiers(Modifiers, Regulator) ->
    with_modifiers(Modifiers, Regulator, fun remove_damper/4).

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
	{_, F} when tuple_size(F) == 2; is_function(F,2) ->
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

			      



remove_damper(Type, _, _, R) ->
    apply_corr(Type, 0, R).


apply_corr(Type, 0, R) ->
    R#rate{active_modifiers = lists:keydelete(
                                Type, 1, R#rate.active_modifiers)};
apply_corr(Type, Corr, R) ->
    ADs = lists:keystore(Type, 1, R#rate.active_modifiers,
			 {Type, Corr}),
    R#rate{active_modifiers = ADs}.



get_rate(#rr {rate = R}) -> R;
get_rate(#cr {rate = R}) -> R;
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
                [] ->
                    reject(From);
                {OldJobs, Q1} ->
                    [timeout(J) || J <- OldJobs],
                    update_queue(q_in(TS, From, Q1), S)
            end;
       true ->
            update_queue(q_in(TS, From, Q), S)
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
    [Name, Mod, MaxTime, MaxSize] = 
        [get_value(K, Opts, Def) || {K, Def} <- [{name, undefined},
                                                 {mod , jobs_queue},
                                                 {max_time, undefined},
                                                 {max_size, undefined}]],
    #queue{} = q_new(Opts, #queue{name = Name,
			  mod = Mod,
			  max_time = MaxTime,
			  max_size = MaxSize}, Mod).

q_new(Options, Q, Mod) ->
    case proplists:get_value(type, Options, fifo) of
        {producer, F} ->
            Q#queue{type = {producer, F}};
        Type ->
	    Mod:new(Options, Q#queue{type = Type})
    end.


q_all     (#queue{mod = Mod} = Q)     -> Mod:all     (Q).
q_timedout(#queue{mod = Mod} = Q)     -> Mod:timedout(Q).
q_delete  (#queue{mod = Mod} = Q)     -> Mod:delete  (Q).
%%
q_is_empty(#queue{type = {producer,_}}) -> false;
q_is_empty(#queue{mod = Mod} = Q)       -> Mod:is_empty(Q).
%%
q_out     (infinity, #queue{mod = Mod} = Q) ->  Mod:all (Q);
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
next_time(_TS, #queue{oldest_job = undefined}) ->
    undefined;
next_time(TS, #queue{latest_dispatch = TS1,
		     check_interval = I0}) ->
    I = case I0 of
	    _ when is_integer(I0) -> I0;
	    {M,F, As} ->
		M:F(TS, TS1, As)
	end,
    Since = (TS - TS1) div 1000,
    erlang:max(0, I - Since).


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

