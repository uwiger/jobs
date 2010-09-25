%%% The contents of this file are subject to the Erlang Public License,
%%% Version 1.0, (the "License"); you may not use this file except in
%%% compliance with the License. You may obtain a copy of the License at
%%% http://www.erlang.org/license/EPL1_0.txt
%%%
%%% Software distributed under the License is distributed on an "AS IS"
%%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%%% the License for the specific language governing rights and limitations
%%% under the License.
%%%
%%% The Original Code is jobs-0.1.
%%%
%%% The Initial Developer of the Original Code is Ericsson AB.
%%% Portions created by Ericsson are Copyright (C), 2006, Ericsson AB.
%%% All Rights Reserved.
%%%
%%% Contributor(s): ______________________________________.

%%%-------------------------------------------------------------------
%%% File    : jobs_server.erl
%%% @author  : Ulf Wiger <ulf.wiger@erlang-solutions.com>
%%% @end
%%% Description : 
%%%
%%% Created : 15 Jan 2010 by Ulf Wiger <ulf.wiger@erlang-solutions.com>
%%%-------------------------------------------------------------------
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

-export([rate_test/1,
	 serial_run/1,
	 parallel_run/1,
	 counter_test/1,
	 start_test_server/1,
	 stop_server/0]).

-compile(export_all).

-import(proplists, [get_value/3]).

-include("jobs.hrl").
-record(st, {queues      = []  :: [#q{}],
	     group_rates = []  :: [#grp{}],
	     counters    = []  :: [#cr{}],  
	     q_select          :: atom(),
	     q_select_st       :: any(),
	     default_queue,
	     interval    = 50  :: integer(),
	     info_f}).


-define(SERVER, ?MODULE).

-include_lib("eunit/include/eunit.hrl").

-opaque counter() :: {any(), any()}.
-type queue_options() :: list().
-type queue_name() :: any().
-type info_category() :: queues | group_rates | counters.

-spec ask() -> {ok, any()} | {error, rejected | timeout}.
%%
ask() ->
    ask(default).


-spec ask(atom()) -> {ok, reg_obj()} | {error, rejected | timeout}.
%%
ask(Type) ->
    case call(?SERVER, {ask, Type, timestamp()}, infinity) of
        {ok, Counters} ->
            [try gproc:reg(?COUNTER(C), V)
             catch
                 error:badarg ->
		     %% failure might mean that we have these counters
		     %% already. Let's try to increment the counters instead;
		     %% if that doesn't work, the call will fail.
                     gproc:update_counter({c,l,C},V)
             end || {C,V} <- Counters],
            {ok, Counters};
        Other ->
            Other
    end.

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
done(Counters) ->
    [catch gproc:unreg(?COUNTER(C)) || {C,_} <- Counters],
    ok.

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
    Opts = case application:get_env(options) of
               {ok, O} when is_list(O) ->
                   O;
	       _ ->
                   []
	   end,
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
                   [#q{name = N}|_] ->
                       N
               end,
    Default = get_value(default_queue, Opts, Default0),
    {ok, set_info(S1#st{queues        = Queues,
                           default_queue = Default,
                           interval      = Interval})}.



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
init_queue({Name, Opts}, S) ->
    [ChkI, Regs] =
        [get_value(K,Opts,D) ||
            {K, D} <- [{check_interval,undefined},
                       {regulators, []}]],
    Q0 = q_new([{name,Name}|Opts]),
    Q1 = init_regulators(Regs, Q0#q{check_interval = ChkI}),
    calculate_check_interval(Q1, S).

calculate_check_interval(#q{regulators = Rs,
                            check_interval = undefined} = Q, S) ->
    Regs = expand_regulators(Rs, S),
    I = lists:foldl(
          fun(R, Acc) ->
		  Rate = get_rate(R),
		  I1 = Rate#rate.interval div 1000,
                  erlang:min(I1, Acc)
          end, infinity, Regs),
    Q#q{check_interval = I};
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

init_regulators(Rs, #q{name = Qname} = Q) ->
    {Rs1,_} = lists:mapfoldl(
		fun({rate, Opts}, {Rx,Cx}) ->
			Name0 = {rate,Qname,Rx},
			R0 = #rate{},
			RR0 = #rr{name = Name0, rate = R0},
                        {init_rate_regulator(Opts, RR0), {Rx+1, Cx}};
		   ({counter, Opts}, {Rx,Cx}) when is_list(Opts) ->
			Name0 = {counter,Qname,Cx},
			CR0 = #cr{name = Name0},
			Name = get_value(name, Opts, CR0#cr.name),
			{init_counter(Opts, CR0#cr{name = Name}), {Rx,Cx+1}};
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
    Q#q{regulators = Rs1}.

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

init_counter(Opts, #cr{name = Name} = CR0) ->
    R = #rate{},
    Limit = get_value(limit, Opts, R#rate.limit),
    Interval = get_value(interval, Opts, ?COUNTER_SAMPLE_INTERVAL),
    Modifiers = get_value(modifiers, Opts, R#rate.modifiers),
    case gproc:where(?AGGR(Name)) of
	P when P == self() ->
	    ok;  % ok to reuse an aggregated counter
	undefined ->
	    gproc:reg(?AGGR(Name))
    end,
    CR0#cr{rate = #rate{limit = Limit,
			interval = Interval,
			preset_limit = Limit,
			modifiers = Modifiers}}.


-spec interval(integer()) -> undefined | integer().
%%
%% Return the sampling interval (in us) based on max frequency.
%% If max frequency is 0, we choose what corresponds to an unlimited interval
%%
interval(0    ) -> undefined;  % greater than any int()
interval(Limit) -> 1000000 div Limit.


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
            {reply, R, set_info(S1)};
        Other ->
            Other
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
        #q{} = Q ->
            {noreply, queue_job(TS, From, Q, S1)};
        false ->
            {reply, badarg, S1}
    end;
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
        #q{} = Q ->
            %% for now, let's be very brutal
            [reject(Client) || {_, Client} = q_all(Q)],
            q_delete(Q),
            {reply, true, S#st{queues = lists:keydelete(Name,#q.name,Qs)}}
    end;
i_handle_call({info, Item}, _, S) ->
    {reply, get_info(Item, S), S};
i_handle_call({queue_info, Name}, _, #st{queues = Qs} = S) ->
    {reply, get_queue_info(Name, Qs), S};
i_handle_call({modify_regulator, Type, Qname, RegName, Opts}, _, S) ->
    case get_queue(Qname, S#st.queues) of
        #q{} = Q ->
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
            try GR = init_group(Opts, #cr{name = Name}),
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


handle_cast({set_modifiers, Modifiers}, #st{queues      = Qs,
					   group_rates = GRs,
					   counters    = Cs} = S) ->
    io:fwrite("~p: set_modifiers (~p)~n", [?MODULE, Modifiers]),
    GRs1 = [apply_modifiers(Modifiers, G) || G <- GRs],
    Cs1  = [apply_modifiers(Modifiers, C) || C <- Cs],
    Qs1  = [apply_modifiers(Modifiers, Q) || Q <- Qs],
    {noreply, S#st{queues = Qs1,
		      group_rates = GRs1,
		      counters = Cs1}}.

handle_info({check_queue, Name}, #st{queues = Qs} = S) ->
    case get_queue(Name, Qs) of
        #q{} = Q ->
            TS = timestamp(),
            Q1 = Q#q{timer = undefined},
            case check_queue(Q1, TS, S) of
                {0, _, _} ->
                    {noreply, update_queue(Q1, S)};
                {N, Counters, Regs} ->
                    Q2 = dispatch_N(N, Counters, Q1),
                    {Q3, S3} = update_regulators(
				 Regs, Q2#q{latest_dispatch = TS}, S),
                    {noreply, update_queue(Q3, S3)}
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
    [extract_name(rec_info(Q)) || Q <- Qs];
get_info(group_rates, #st{group_rates = Gs}) ->
    [extract_name(rec_info(G)) || G <- Gs];
get_info(counters, #st{counters = Cs}) ->
    [extract_name(rec_info(C)) || C <- Cs].

get_queue_info(Name, Qs) ->
    case get_queue(Name, Qs) of
        false ->
            undefined;
        #action{type = Type} ->
            [{name, Name},
             {action, Type}];
        Q ->
            rec_info(Q)
    end.

rec_info(R) ->
    Attrs = case R of
                #rr {} -> record_info(fields,rr);
                #cr {} -> record_info(fields,cr);
                #grp{} -> record_info(fields,grp);
                #q  {} -> record_info(fields,q)
            end,
    lists:zipwith(fun(A,P) -> {A, element(P,R)} end, 
                  Attrs, lists:seq(2,tuple_size(R))).


extract_name(L) ->
    Name = proplists:get_value(name, L, '#no_name#'),
    {Name, lists:keydelete(name, 1, L)}.

                     


get_queue(Name, Qs) ->
    lists:keyfind(Name, #q.name, Qs).

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


do_modify_regulator(Type, Name, Opts, #q{} = Q) ->
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

do_modify_rate_regulator(Name, Opts, #q{regulators = Regs} = Q) ->
    case lists:keyfind(Name, #rr.name, Regs) of
        #rr{} = RR ->
            try RR1 = init_rate_regulator(Opts, RR),
                Q#q{regulators = lists:keyreplace(
                                           Name,#rr.name,Regs,RR1)}
            catch
                error:_ ->
                    badarg
            end;
        _ ->
            badarg
    end.

do_modify_counter_regulator(Name, Opts, #q{regulators = Regs} = Q) ->
    case lists:keyfind(Name, #rr.name, Regs) of
        #cr{} = CR ->
            try CR1 = init_counter(Opts, CR),
                Q#q{regulators = lists:keyreplace(
				   Name,#cr.name,Regs,CR1)}
            catch
                error:_ ->
                    badarg
            end;
        _ ->
            badarg
    end.

check_queue(#q{regulators = Regs0} = Q, TS, S) ->
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



expand_regulators([{group_rate, R}|Regs], #st{group_rates = GR} = S) ->
    include_regulator(get_group(R, GR), Regs, S);
expand_regulators([{counter, C}|Regs], #st{counters = Cs} = S) ->
    include_regulator(get_counter(C, Cs), Regs, S);
expand_regulators([#rr{} = R|Regs], S) ->
    [R|expand_regulators(Regs, S)];
expand_regulators([#cr{} = R|Regs], S) ->
    [R|expand_regulators(Regs, S)];
expand_regulators([], _) ->
    [].

update_regulators(Regs, Q0, S0) ->
    lists:foldl(
      fun(#grp{name = R} = GR, {Q, #st{group_rates = GRs} = S}) ->
	      GR1 = GR#grp{latest_dispatch = Q#q.latest_dispatch},
              S1 = S#st{group_rates = update_group(R, GRs, GR1)},
              {Q, S1};
         (#rr{} = RR, {#q{regulators = Rs} = Q, S}) ->
              %% There can be at most one rate regulator
              Q1 = Q#q{regulators = update_rate_regulator(RR, Rs)},
              {Q1, S};
         (#cr{name = R,
              shared = true} = CR, {Q, #st{counters = Cs} = S}) ->
              S1 = S#st{counters = update_counter(R, Cs, CR)},
              {Q, S1};
         (#cr{name = R} = CR, {#q{regulators = Rs} = Q, S}) ->
              Q1 = Q#q{regulators = update_counter(R, Rs, CR)},
              {Q1, S}
      end, {Q0, S0}, Regs).

include_regulator(false, Regs, S) ->
    expand_regulators(Regs, S);
include_regulator(R, Regs, S) ->
    [R|expand_regulators(Regs, S)].


-spec check_regulators([regulator()], #q{}, timestamp()) ->
			      {integer(), [any()]}.
%%
check_regulators(Regs, TS, #q{latest_dispatch = TL}) ->
    check_regulators(Regs, TS, TL, infinity, []).

check_regulators([R|Regs], TS, TL, N, Cs) ->
    case R of
	#rr{rate = #rate{interval = I}} ->
	    N1 = check_rr(I, TS, TL),
	    check_regulators(Regs, TS, TL, erlang:min(N, N1), Cs);
	#grp{rate = #rate{interval = I}, latest_dispatch = TLg} ->
	    N1 = check_rr(I, TS, TLg),
	    check_regulators(Regs, TS, TL, erlang:min(N, N1), Cs);
	#cr{name = Name, increment = I, rate = #rate{limit = Max}} ->
	    C1 = check_cr(Name, I, Max),
	    Cs1 = if C1 == 0 ->
			  Cs;
		     true ->
			  [{Name, C1}|Cs]
		  end,
	    check_regulators(Regs, TS, TL, erlang:min(C1, N), Cs1)
    end;
check_regulators([], _, _, N, Cs) ->
    {N, Cs}.

check_rr(undefined, _, _) ->
    0;
check_rr(I, TS, TL) ->
    trunc((TS - TL)/I).

check_cr(Name, Incr, Max) ->
    try Cur = gproc:get_value(?AGGR(Name)),
	 case Max - Cur of
	     N when N > 0 ->
		 N div Incr;
	     _ ->
		 0
	 end
    catch
        error:_ ->
            0
    end.

-spec dispatch_N(integer() | infinity, [any()], #q{}) -> #q{}.
%%			
dispatch_N(N, Counters, Q) ->
    {Jobs, Q1} = q_out(N, Q),
    [approve(Client, Counters) || {_, Client} <- Jobs],
    Q1.


update_queue(#q{name = N} = Q, #st{queues = Qs} = S) ->
    Q1 = start_timer(Q),
    S#st{queues = lists:keyreplace(N, #q.name, Qs, Q1)}.

start_timer(#q{timer = TRef} = Q) when TRef =/= undefined ->
    Q;
start_timer(#q{name = Name} = Q) ->
    case next_time(timestamp(), Q) of
        T when is_integer(T) -> 
            Msg = {check_queue, Name},
            TRef = do_send_after(T, Msg),
            Q#q{timer = TRef};
        undefined ->
            Q
    end.

next_time(TS, TSl, I) ->
    Since = (TS - TSl) div 1000,
    erlang:max(0, I - Since).

do_send_after(T, Msg) ->
    erlang:send_after(T, self(), Msg).

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
    R1 = apply_active_modifiers(Modifiers, R0),
    set_rate(R1, Regulator).



apply_damper(Type, Local, Remote, R) ->
    case lists:keyfind(Type, 1, R#rate.modifiers) of
	false ->
	    %% no effect on this regulator
	    R;
	{_, Unit} when is_integer(Unit) ->
            %% The active_modifiers list is kept up-to-date in order 
            %% to support remove_damper().
            Corr = Local * Unit,
	    apply_corr(Type, Corr, R);
	{_, F} when tuple_size(F) == 2; is_function(F,2) ->
	    case F(Local, Remote) of
		Corr when is_integer(Corr) ->
		    apply_corr(Type, Corr, R)
	    end
    end.


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


apply_active_modifiers(ADs, #rate{preset_limit = Preset} = R) ->
    Limit = lists:foldl(
	      fun({_,Corr}, L) ->
		      L - (Corr*Preset/100)
	      end, Preset, ADs),
    R#rate{limit = Limit,
	   interval = interval(Limit),
	   active_modifiers = ADs}.
    
		 

queue_job(TS, From, #q{max_size = MaxSz} = Q, S) ->
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
    #q{} = Mod:new(Opts, #q{name = Name,
                            mod = Mod,
                            max_time = MaxTime,
                            max_size = MaxSize}).

q_all     (#q{mod = Mod} = Q)     -> Mod:all     (Q).
q_is_empty(#q{mod = Mod} = Q)     -> Mod:is_empty(Q).
q_timedout(#q{mod = Mod} = Q)     -> Mod:timedout(Q).
q_delete  (#q{mod = Mod} = Q)     -> Mod:delete  (Q).
%%
q_out     (infinity, #q{mod = Mod} = Q) ->  Mod:all (Q);
q_out     (N , #q{mod = Mod} = Q) -> Mod:out     (N, Q).
q_info    (I , #q{mod = Mod} = Q) -> Mod:info    (I, Q).
%%
q_in(TS, From, #q{mod = Mod} = Q) -> Mod:in(TS, From, Q).

%% End queue accessor functions.
%% ===========================================================

-spec next_time(TS :: integer(), #q{}) -> integer() | undefined.
%%
%% Calculate the delay (in ms) until queue is checked again.
%%
next_time(_TS, #q{oldest_job = undefined}) ->
    undefined;
next_time(TS, #q{latest_dispatch = TS1,
                 check_interval = I}) ->
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



%%%=================================================================
%%% EUnit Test Code
%%%=================================================================

rate_test_() ->
    [fun() -> rate_test(R) end || R <- [1,5,10,100]]
	++ [fun() -> counter_test(C) end || C <- [1,5,10]]
	++ [fun() -> group_rate_test(R) end || R <- [10,50,100]].
		    

rate_test(Rate) ->
    start_test_server({rate,Rate}),
    serial_run(Rate),
    stop_server().


serial_run(N) ->
    Res = tc(fun() -> run_jobs(q,N) end),
    io:fwrite(user, "Rate: ~p, Res = ~p~n", [N,Res]).

parallel_run(N) ->
    Res = tc(fun() -> pmap(fun() ->
				   run(q, one_job(time))
			   end, N)
	     end),
    io:fwrite(user, "Rate: ~p, Res = ~p~n", [N,Res]).
    
		      


counter_test(Count) ->
    start_test_server({count,Count}),
    Res = tc(fun() ->
		     pmap(fun() -> run(q, one_job(count)) end, Count * 2)
	     end),
    io:fwrite(user, "~p~n", [Res]),
    stop_server().

group_rate_test(Rate) ->
    start_test_server([{rate,Rate * 2},{group,Rate}]),
    serial_run(Rate),
    stop_server().
    
		      

pmap(F, N) ->
    Pids = [spawn_monitor(fun() -> exit(F()) end) || _ <- lists:seq(1,N)],
    collect(Pids).

collect([{_P,Ref}|Ps]) ->
    receive
	{'DOWN', Ref, _, _, Res} ->
	    [Res|collect(Ps)]
    end;
collect([]) ->
    [].
			       

start_test_server({rate,Rate}) ->
    start_link([{queues, [{q, [{regulators,
                                [{rate,[
                                        {limit, Rate}]
                                 }]}
                              ]}
                         ]}
               ]);
start_test_server([{rate,Rate},{group,Grp}]) ->
    start_link([{group_rates, [{gr, [{limit, Grp}]}]},
		{queues, [{q, [{regulators,
				[{rate,[{limit, Rate}]},
				 {group_rate, gr}]}
			      ]}
			 ]}
		]);
start_test_server({count, Count}) ->
    application:start(gproc),
    start_link([{queues, [{q, [{regulators,
                                [{counter,[
					   {limit, Count}
					  ]
                                 }]}
                              ]}
                         ]}
               ]).


stop_server() ->
    unlink(whereis(?MODULE)),
    Ref = erlang:monitor(process, ?MODULE),
    exit(whereis(?MODULE), done),
    %% make sure it's really down before returning:
    receive {'DOWN',Ref,_,_,_} ->
            ok
    end.


tc(F) ->
    T1 = erlang:now(),
    R = (catch F()),
    T2 = erlang:now(),
    {timer:now_diff(T2,T1), R}.

run_jobs(Q,N) ->
    [run(Q, one_job(time)) || _ <- lists:seq(1,N)].

one_job(time) ->
    fun timestamp/0;
one_job(count) ->
    fun() ->
	    gproc:select(a,[{{{'_',l,'$1'},'_','$2'},[],[{{'$1','$2'}}]}])
    end.
