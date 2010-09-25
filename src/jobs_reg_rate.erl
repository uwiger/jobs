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
%%% File    : jobs_reg_rate.erl
%%% @author  : Ulf Wiger <ulf.wiger@erlang-solutions.com>
%%% @end
%%% Description : 
%%%
%%% Created : 15 Jan 2010 by Ulf Wiger <ulf.wiger@erlang-solutions.com>
%%%-------------------------------------------------------------------
-module(jobs_reg_rate).
-behaviour(jobs_regulator).


-export([set_modifiers/1]).


-import(proplists, [get_value/3]).

-include("jobs.hrl").

-include_lib("eunit/include/eunit.hrl").


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
                               
init_group(Opts, G) ->
    R = #rate{},
    Limit = get_value(limit, Opts, R#rate.limit),
    Modifiers = get_value(modifiers, Opts, R#rate.modifiers),
    Interval = interval(Limit),
    G#grp{rate = #rate{limit = Limit,
		       preset_limit = Limit,
		       modifiers = Modifiers,
		       interval = Interval}}.



init(Opts) ->
    R0 = #rate{},
    Limit     = get_value(limit    , Opts, R0#rate.limit),
    Modifiers = get_value(modifiers, Opts, R0#rate.modifiers),
    Interval = interval(Limit),
    #rate{limit = Limit,
          interval = Interval,
          preset_limit = Limit,
          modifiers = Modifiers}.


interval(0    ) -> undefined;  % greater than any int()
interval(Limit) -> 1000000 div Limit.




handle_info({check_queue, Name}, #state{queues = Qs} = S) ->
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

get_info(queues, #state{queues = Qs}) ->
    [extract_name(rec_info(Q)) || Q <- Qs];
get_info(group_rates, #state{group_rates = Gs}) ->
    [extract_name(rec_info(G)) || G <- Gs];
get_info(counters, #state{counters = Cs}) ->
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

                     


check_queue(#q{regulators = Regs0} = Q, TS, S) ->
    case q_is_empty(Q) of
        true ->
            %% no action necessary
            {0, [], []};
        false ->
            %% non-empty queue
            Regs = expand_regulators(Regs0, S),
            {N, Counters} = case check_regulators(Regs, Q, TS) of
                                0 -> {0,[]};
                                Nx ->
                                    {Nx, [{C,1} || #cr{name = C} <- Regs]}
                            end,
            {N, Counters, Regs}
    end.



update_regulators(Regs, Q0, S0) ->
    lists:foldl(
      fun(#grp{name = R} = GR, {Q, #state{group_rates = GRs} = S}) ->
	      GR1 = GR#grp{latest_dispatch = Q#q.latest_dispatch},
              S1 = S#state{group_rates = update_group(R, GRs, GR1)},
              {Q, S1};
         (#rr{} = RR, {#q{regulators = Rs} = Q, S}) ->
              %% There can be at most one rate regulator
              Q1 = Q#q{regulators = update_rate_regulator(RR, Rs)},
              {Q1, S};
         (#cr{name = R,
              shared = true} = CR, {Q, #state{counters = Cs} = S}) ->
              S1 = S#state{counters = update_counter(R, Cs, CR)},
              {Q, S1};
         (#cr{name = R} = CR, {#q{regulators = Rs} = Q, S}) ->
              Q1 = Q#q{regulators = update_counter(R, Rs, CR)},
              {Q1, S}
      end, {Q0, S0}, Regs).


check_regulators(Regs, Q, TS) ->
    check_regulators(Regs, Q, TS, infinity).

check_regulators([R|Regs], Q, TS, Sofar) ->
    case check(R, Q, TS) of
        0 -> 0;
        N -> check_regulators(Regs, Q, TS, erlang:min(N, Sofar))
    end;
check_regulators([], _, _, Sofar) ->
    Sofar.

check(#rr{rate = #rate{interval = I}}, #q{latest_dispatch = TL}, TS) ->
    if I == undefined ->
            0;
       true ->
            trunc((TS - TL)/I)
    end;
check(#grp{rate = #rate{interval = I}, latest_dispatch = TL}, _, TS) ->
    if I == undefined ->
            0;
       true ->
            trunc((TS - TL)/I)
    end;    
check(#cr{name = Name, rate = #rate{limit = Max}}, _, _) ->
    try Cur = gproc:get_value(?AGGR(Name)),
        erlang:max(0, Max - Cur)
    catch
        error:_ ->
            0
    end.


update_queue(#q{name = N} = Q, #state{queues = Qs} = S) ->
    Q1 = start_timer(Q),
    S#state{queues = lists:keyreplace(N, #q.name, Qs, Q1)}.

start_timer(#q{timer = TRef} = Q) when TRef =/= undefined ->
    Q;
start_timer(#q{oldest_job = undefined} = Q) ->
    %% empty queue
    Q;
start_timer(#q{name = N,
               latest_dispatch = TSl,
               check_interval = I} = Q) ->
    Msg = {check_queue, N},
    T = next_time(timestamp(), TSl, I),
    TRef = do_send_after(T, Msg),
    Q#q{timer = TRef};
start_timer(Q) ->
    Q.

next_time(TS, TSl, I) ->
    Since = (TS - TSl) div 1000,
    erlang:max(0, I - Since).


apply_modifier(Type, Local, Remote, R) ->
    case lists:keyfind(Type, 1, R#rate.modifiers) of
	false ->
	    %% no effect on this regulator
	    R;
	{_, Unit} when is_integer(Unit) ->
            %% The active_modifiers list is kept up-to-date in order 
            %% to support remove_modifier().
            Corr = Local * Unit,
	    apply_corr(Type, Corr, R);
	{_, F} when tuple_size(F) == 2; is_function(F,2) ->
	    case F(Local, Remote) of
		Corr when is_integer(Corr) ->
		    apply_corr(Type, Corr, R)
	    end
    end.


remove_modifier(Type, _, _, R) ->
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
		      L - Corr
	      end, Preset, ADs),
    R#rate{limit = Limit,
	   interval = interval(Limit),
	   active_modifiers = ADs}.
    
