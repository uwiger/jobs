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
%%% File    : jobs_sampler.erl
%%% @author  : Ulf Wiger <ulf.wiger@erlang-solutions.com>
%%% @end
%%% Description : 
%%%
%%% Created : 15 Jan 2010 by Ulf Wiger <ulf.wiger@erlang-solutions.com>
%%%-------------------------------------------------------------------
-module(jobs_sampler).

-compile(export_all).
-include_lib("parse_trans/include/exprecs.hrl").

-record(indicators, {mnesia_dumper = 0,
                     mnesia_tm = 0,
                     mnesia_remote = []}).

-record(sampler, {name,
                  mod,
                  mod_state,
                  type,    % binary | meter
                  step,    % {seconds, [{Secs,Step}]}|{levels,[{Level,Step}]}
		  hist_length = 10,
                  history = queue:new()}).


-export_records([indicators]).

-record(state, {modified = false,
		update_delay = 500,
		indicators = [],
		remote_indicators = [],
                samplers = []               :: [#sampler{}],
                dampers = orddict:new(),
		remote_dampers = []}).


behaviour_info(callbacks) ->
    [{init, 1},
     {sample, 2},
     {handle_msg, 3},
     {calc, 2}].


trigger_sample() ->
    gen_server:cast(?MODULE, sample).

start_link() ->
    start_link([]).

start_link(Opts) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Opts, []).


%% ==========================================================
%% Gen_server callbacks

init(Opts) ->
    Samplers = init_samplers(Opts),
    mnesia:subscribe(system),
    timer:apply_interval(10000, ?MODULE, trigger_sample, []),
    gen_server:abcast(nodes(), ?MODULE, {get_status, node()}),
    % [{?MODULE,N} ! {get_status,node()} || N <- nodes()],
    {ok, #state{samplers = Samplers}}.


handle_info({?MODULE, update}, #state{modified = IsModified} = S) ->
    case IsModified of
	true ->
	    {noreply, set_dampers(S#state{modified = false})};
	false ->
	    {noreply, S}
    end;
handle_info(Msg, #state{samplers = Samplers0} = S) ->
    Samplers = map_handle_info(Msg, Samplers0),
    {noreply, calc_dampers(S#state{samplers = Samplers})}.


handle_cast({get_status, Node}, S) ->
    tell_node(Node, S),
    {noreply, S};
handle_cast(sample, #state{samplers = Samplers0} = S) ->
    % Flags = mnesia_overload_read(),
    % Dumper = value(proplists:get_value(mnesia_dump_log, Flags, false)),
    % MsgQ   = value(proplists:get_value(mnesia_tm, Flags, false)),
    Samplers = collect_samples(Samplers0),
    {noreply, calc_dampers(S#state{samplers = Samplers})};
handle_cast({remote, Node, Dampers}, #state{remote_dampers = Ds} = S) ->
    NewDs =
	lists:keysort(1, ([{{K,Node},V} || {K,V} <- Dampers]
			  ++ [D || {{_,N},_} = D <- Ds, N =/= Node])),
    {noreply, calc_dampers(S#state{remote_dampers = NewDs})}.


terminate(_, _S) ->
    ok.


code_change(_FromVsn, State, _Extra) ->
    {ok, State}.

%% end Gen_server callbacks
%% ==========================================================


init_samplers(Opts) ->
    Samplers = proplists:get_value(samplers, Opts, []),
    lists:map(
      fun({Name, Mod, Args}) ->
	      {ok, ModSt} = Mod:init(Args),
	      #sampler{name = Name,
		       mod = Mod,
		       mod_state = ModSt}
      end, Samplers).



group_dampers(Local, Remote) ->
    RemoteRegrouped = lists:foldl(
			fun({{K,N},V}, D) ->
				orddict:append(K,{N,V},D)
			end, orddict:new(), Remote),
    [{K, V, remote_dampers(K,RemoteRegrouped)}
     || {K,V} <- Local]
	++
	[{K, 0, Vs} || {K,Vs} <- RemoteRegrouped,
		       not lists:keymember(K, 1, Local)].

remote_dampers(K, Remote) ->
    case orddict:find(K, Remote) of
	{ok, Vs} ->
	    Vs;
	error ->
	    []
    end.


collect_samples(Samplers) ->
    [one_sample(S) || S <- Samplers].


one_sample(#sampler{mod = M,
                    mod_state = ModS} = Sampler) ->
    Timestamp = timestamp(),
    try {Res, NewModS} = M:sample(Timestamp, ModS),
	add_to_history(Res, Timestamp,
		       Sampler#sampler{mod_state = NewModS})
    catch
        error:Err ->
	    sampler_error(Err, Sampler)
    end.


map_handle_info(Msg, Samplers) ->
    Timestamp = timestamp(),
    [one_handle_info(Msg, Timestamp, S) || S <- Samplers].

one_handle_info(Msg, TS, #sampler{mod = M, mod_state = ModS} = Sampler) ->
    try M:handle_msg(Msg, TS, ModS) of
	{ignore, ModS1} ->
	    Sampler#sampler{mod_state = ModS1};
	{log, Sample, ModS1} ->
	    add_to_history(Sample, TS, Sampler#sampler{mod_state = ModS1})
    catch
	error:Err ->
	    sampler_error(Err, Sampler)
    end.


add_to_history(Result, Timestamp, #sampler{hist_length = Len,
					   history = History} = S) ->
    Item = {Timestamp, Result},
    NewHistory =
	case queue:len(History) of
	    HL when HL >= Len ->
		queue:in(Item, queue:drop(History));
	    _ ->
		queue:in(Item, History)
	end,
    S#sampler{history = NewHistory}.


sampler_error(Err, Sampler) ->
    error_logger:error_msg([{?MODULE, sampler_error},
			    {error, Err},
			    {sampler, Sampler}]),
    % For now, don't modify the sampler (disable it...?)
    Sampler.


set_dampers(#state{dampers = Local, remote_dampers = Remote} = S) ->
    Grouped = group_dampers(Local, Remote),
    jobs_server:set_dampers(Grouped),
    S.


calc_dampers(#state{samplers = Samplers} = S) ->
    S1 = calc_dampers(Samplers, S),
    case S1#state.modified of
	false ->
	    erlang:send_after(S#state.update_delay, self(), {?MODULE,update}),
	    S1#state{modified = true};
	true ->
	    S1
    end.

calc_dampers(Samplers, #state{dampers = Dampers0} = S) ->
    {Samplers1, Dampers1} =
	lists:mapfoldl(
	  fun(#sampler{mod = M,
		       mod_state = ModS,
		       history = History} = Sx, Acc) ->
		  try {NewDampers, NewModSt} = M:calc(History, ModS),
		      {Sx#sampler{mod_state = NewModSt},
		       merge_dampers(orddict:from_list(NewDampers), Acc)}
		  catch
		      error:Err ->
			  sampler_error(Err, Sx),
			  {Sx, Acc}
		  end
	  end, Dampers0, Samplers),
    {Samplers1, S#state{dampers = Dampers1}}.


merge_dampers(New, Dampers) ->
    orddict:merge(
      fun(_, V1, V2) -> erlang:max(V1, V2) end, New, Dampers).


mnesia_overload_read() ->
    %% This function is not present in older mnesia versions
    %% (or currently indeed in /any/ official version.)
    case erlang:function_exported(mnesia_lib,overload_read,0) of
	false ->
	    [];
	true ->
	    mnesia_lib:overload_read()
    end.


notify_others(States) ->
    [case X of
        {X1,X1} -> ignore;
        {X2,_} ->
             [{?MODULE,N} ! {remote, Msg, node(), X2} || N <- nodes()]
     end || {Msg, X} <- States].


% calc_dampers(New, #state{dampers = Ds0} = S) ->
%     S1 = update_state(New, S),
%     Ds1 = calc_dampers(S1),
%     if Ds1 == Ds0 ->
%             S1;
%        true ->
%             notify_others(Ds1),
%             io:fwrite("applying dampers ~p~n", [Ds1]),
%             jobs_server:set_dampers(Ds1),
%             S1#state{dampers = Ds1}
%     end.


% update_state(New, S) ->
%     Is = '#set-indicators'(New, S#state.indicators),
%     S#state{indicators = Is}.
              
    
% calc_dampers(#state{indicators = Is}) ->
%     MnesiaInds = [mnesia_dumper,
%                   mnesia_tm,
%                   mnesia_remote],
%     [MD, MT, R] = '#get-indicators'(MnesiaInds, Is),
%     ordsets:from_list([{mnesia, MD + MT + value(R)} |
%                        '#get-indicators'(
%                          '#info-indicators'(fields) -- MnesiaInds, Is)]).

tell_node(Node, S) ->
    gen_server:cast({?MODULE, Node}, {remote, node(), calc_dampers(S)}).


value(false) -> 0;
value(true ) -> 1;
value([]   ) -> 0;
value([_|_]) -> 1.




%% example: type = time , step = {seconds, [{0,1},{30,2},{45,3},{50,4}]}
%%          type = value, step = [{80,1},{85,2},{90,3},{95,4},{100,5}]

calc(time, Template, History) ->
    Now = timestamp(),
    {Unit, Steps} = case Template of
			T when is_list(T) ->
			    {msec, T};
			{U, [_|_] = T} when U==sec; U==msec ->
			    {U, T}
		    end,
    case take_last(fun({V,_}) -> V == true end, History) of
        [] -> 0;
        {Since,_} ->
            %% timestamps are in milliseconds
            Time = case Unit of
		       sec  -> (Now - Since) div 1000;
		       msec -> Now - Since
		   end,
            pick_step(Time, Steps)
    end;
calc(value, Levels, History) ->
    case History of
        [] -> 0;
        [{_, Level}|_] ->
            pick_step(Level, Levels)
    end.


take_last(F, L) ->
    take_last(F, L, []).

take_last(F, [H|T], Last) ->
    case F(H) of
        true  -> take_last(F, T, H);
        false -> Last
    end;
take_last(_, [], Last) ->
    Last.


pick_step(Level, Ls) ->
    take_last(fun({L,_}) ->
                      Level > L
              end, Ls, 0).


%% millisecond timestamp, never wraps
timestamp() ->
    jobs_server:timestamp() div 1000.
