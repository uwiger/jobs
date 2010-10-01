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
%% File    : jobs_sampler.erl
%% @author  : Ulf Wiger <ulf.wiger@erlang-solutions.com>
%% @end
%% Description : 
%%
%% Created : 15 Jan 2010 by Ulf Wiger <ulf.wiger@erlang-solutions.com>
%%-------------------------------------------------------------------
-module(jobs_sampler).

-export([start_link/0, start_link/1,
	 trigger_sample/0,
	 tell_sampler/2,
	 calc/3]).

-export([init/1,
	 behaviour_info/1,
	 handle_call/3,
	 handle_cast/2,
	 handle_info/2,
	 terminate/2,
	 code_change/3]).

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

-define(SAMPLE_INTERVAL, 10000).


-export_records([indicators]).

-record(state, {modified = false,
		update_delay = 500,
		indicators = [],
		remote_indicators = [],
                samplers = []               :: [#sampler{}],
                modifiers = orddict:new(),
		remote_modifiers = []}).


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


tell_sampler(P, Msg) ->
    gen_server:call(?MODULE, {tell_sampler, P, timestamp(), Msg}).

%% ==========================================================
%% Gen_server callbacks

init(Opts) ->
    Samplers = init_samplers(Opts),
    timer:apply_interval(?SAMPLE_INTERVAL, ?MODULE, trigger_sample, []),
    gen_server:abcast(nodes(), ?MODULE, {get_status, node()}),
    {ok, #state{samplers = Samplers}}.


handle_call({tell_sampler, Name, TS, Msg}, _From, #state{samplers = Samplers0} = St) ->
    case lists:keyfind(Name, #sampler.name, Samplers0) of
	false ->
	    {reply, {error, not_found}, St};
	#sampler{} = Sampler ->
	    Sampler1 = one_handle_info(Msg, TS, Sampler),
	    Samplers1 = lists:keyreplace(Name, #sampler.name, Samplers0, Sampler1),
	    {reply, ok, St#state{samplers = Samplers1}}
    end.
		

handle_info({?MODULE, update}, #state{modified = IsModified} = S) ->
    case IsModified of
	true ->
	    {noreply, set_modifiers(S#state{modified = false})};
	false ->
	    {noreply, S}
    end;
handle_info(Msg, #state{samplers = Samplers0} = S) ->
    Samplers = map_handle_info(Msg, Samplers0),
    {noreply, calc_modifiers(S#state{samplers = Samplers})}.


handle_cast({get_status, Node}, S) ->
    tell_node(Node, S),
    {noreply, S};
handle_cast(sample, #state{samplers = Samplers0} = S) ->
    Samplers = collect_samples(Samplers0),
    {noreply, calc_modifiers(S#state{samplers = Samplers})};
handle_cast({remote, Node, Modifiers}, #state{remote_modifiers = Ds} = S) ->
    NewDs =
	lists:keysort(1, ([{{K,Node},V} || {K,V} <- Modifiers]
			  ++ [D || {{_,N},_} = D <- Ds, N =/= Node])),
    {noreply, calc_modifiers(S#state{remote_modifiers = NewDs})}.


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
	      {ok, ModSt} = Mod:init(Name, Args),
	      #sampler{name = Name,
		       mod = Mod,
		       mod_state = ModSt}
      end, Samplers).



group_modifiers(Local, Remote) ->
    RemoteRegrouped = lists:foldl(
			fun({{K,N},V}, D) ->
				orddict:append(K,{N,V},D)
			end, orddict:new(), Remote),
    [{K, V, remote_modifiers(K,RemoteRegrouped)}
     || {K,V} <- Local]
	++
	[{K, 0, Vs} || {K,Vs} <- RemoteRegrouped,
		       not lists:keymember(K, 1, Local)].

remote_modifiers(K, Remote) ->
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
    error_logger:error_report([{?MODULE, sampler_error},
			       {error, Err},
			       {sampler, Sampler}]),
    % For now, don't modify the sampler (disable it...?)
    Sampler.


set_modifiers(#state{modifiers = Local, remote_modifiers = Remote} = S) ->
    Grouped = group_modifiers(Local, Remote),
    jobs_server:set_modifiers(Grouped),
    S.


calc_modifiers(#state{samplers = Samplers} = S) ->
    S1 = calc_modifiers(Samplers, S),
    case S1#state.modified of 
	true ->
	    erlang:send_after(S#state.update_delay, self(), {?MODULE,update});
	false ->
	    skip
    end,
    S1.


calc_modifiers(Samplers, #state{modifiers = Modifiers0} = S) ->
    {Samplers1, {Modifiers1, IsModified}} =
	lists:mapfoldl(
	  fun(#sampler{mod = M,
		       mod_state = ModS,
		       history = History} = Sx, {Acc,Flg}) ->
		  try M:calc(History, ModS) of
		      {NewModifiers, NewModSt} ->
			  {Sx#sampler{mod_state = NewModSt},
			   {merge_modifiers(orddict:from_list(NewModifiers), Acc), true}};
		      false ->
			  {Sx, {Acc, Flg}}
		  catch
		      error:Err ->
			  sampler_error(Err, Sx),
			  {Sx, {Acc,Flg}}
		  end
	  end, {Modifiers0, false}, Samplers),
    S#state{samplers = Samplers1, modifiers = Modifiers1, modified = IsModified}.


merge_modifiers(New, Modifiers) ->
    orddict:merge(
      fun(_, V1, V2) -> erlang:max(V1, V2) end, New, Modifiers).



%% notify_others(States) ->
%%     [case X of
%%         {X1,X1} -> ignore;
%%         {X2,_} ->
%%              [{?MODULE,N} ! {remote, Msg, node(), X2} || N <- nodes()]
%%      end || {Msg, X} <- States].


% calc_modifiers(New, #state{modifiers = Ds0} = S) ->
%     S1 = update_state(New, S),
%     Ds1 = calc_modifiers(S1),
%     if Ds1 == Ds0 ->
%             S1;
%        true ->
%             notify_others(Ds1),
%             io:fwrite("applying modifiers ~p~n", [Ds1]),
%             jobs_server:set_modifiers(Ds1),
%             S1#state{modifiers = Ds1}
%     end.


% update_state(New, S) ->
%     Is = '#set-indicators'(New, S#state.indicators),
%     S#state{indicators = Is}.
              
    
% calc_modifiers(#state{indicators = Is}) ->
%     MnesiaInds = [mnesia_dumper,
%                   mnesia_tm,
%                   mnesia_remote],
%     [MD, MT, R] = '#get-indicators'(MnesiaInds, Is),
%     ordsets:from_list([{mnesia, MD + MT + value(R)} |
%                        '#get-indicators'(
%                          '#info-indicators'(fields) -- MnesiaInds, Is)]).

tell_node(Node, S) ->
    gen_server:cast({?MODULE, Node}, {remote, node(), calc_modifiers(S)}).


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
