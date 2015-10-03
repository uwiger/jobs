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
%% File    : jobs_sampler.erl
%% @author  : Ulf Wiger <ulf@wiger.net>
%% @end
%% Description :
%%
%% Created : 15 Jan 2010 by Ulf Wiger <ulf@wiger.net>
%%-------------------------------------------------------------------
-module(jobs_sampler).

-export([start_link/0, start_link/1,
	 trigger_sample/0,
	 tell_sampler/2,
	 subscribe/0,
	 end_subscription/0,
	 calc/3]).

-export([init/1,
	 behaviour_info/1,
	 handle_call/3,
	 handle_cast/2,
	 handle_info/2,
	 terminate/2,
	 code_change/3]).

-include("jobs.hrl").

%% -record(indicators, {mnesia_dumper = 0,
%%                      mnesia_tm = 0,
%%                      mnesia_remote = []}).


-define(SAMPLE_INTERVAL, 10000).


-record(state, {modified = false,
		update_delay = 0,
		sample_interval = ?SAMPLE_INTERVAL,
		%% indicators = [],
		%% remote_indicators = [],
                samplers = []               :: [#sampler{}],
		subscribers = [],
                modifiers = orddict:new(),
		remote_modifiers = []}).


behaviour_info(callbacks) ->
    [{init, 2},
     {sample, 2},
     {handle_msg, 3},
     {calc, 2}].


trigger_sample() ->
    gen_server:cast(?MODULE, sample).

start_link() ->
    Opts = application:get_all_env(jobs),
    start_link(Opts).

start_link(Opts) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Opts, []).


tell_sampler(P, Msg) ->
    gen_server:call(?MODULE, {tell_sampler, P, timestamp(), Msg}).

%% @spec subscribe() -> ok
%% @doc Subscribes to feedback indicator information
%%
%% This function allows a process to receive the same information as the
%% jobs_server any time the information changes.
%%
%% The notifications are delivered on the format `{jobs_indicators, Info}',
%% where
%% <pre>
%% Info :: [{IndicatorName, LocalValue, Remote}]
%%  Remote :: [{NodeName, Value}]
%% </pre>
%%
%% This information could be used e.g. to aggregate the information and generate
%% new sampler information (which could be passed to a sampler plugin using
%% {@link tell_sampler/2}, or to a specific queue using {@link jobs:ask_queue/2}.
%%
subscribe() ->
    gen_server:call(?MODULE, subscribe).

%%
end_subscription() ->
    gen_server:call(?MODULE, end_subscription).

%% ==========================================================
%% Gen_server callbacks

init(Opts) ->
    Samplers = init_samplers(Opts),
    S0 = #state{samplers = Samplers},
    UpdateDelay = proplists:get_value(
		    sample_update_delay, Opts, S0#state.update_delay),
    SampleInterval = proplists:get_value(
		       sample_interval, Opts, S0#state.sample_interval),
    timer:apply_interval(SampleInterval, ?MODULE, trigger_sample, []),
    gen_server:abcast(nodes(), ?MODULE, {get_status, node()}),
    {ok, #state{samplers = Samplers,
		update_delay = UpdateDelay,
		sample_interval = SampleInterval}}.


handle_call({tell_sampler, Name, TS, Msg}, _From, #state{samplers = Samplers0} = St) ->
    case lists:keyfind(Name, #sampler.name, Samplers0) of
	false ->
	    {reply, {error, not_found}, St};
	#sampler{} = Sampler ->
	    Sampler1 = one_handle_info(Msg, TS, Sampler),
	    Samplers1 = lists:keyreplace(Name, #sampler.name, Samplers0, Sampler1),
	    {reply, ok, St#state{samplers = Samplers1}}
    end;
handle_call(subscribe, {Pid,_}, #state{subscribers = Subs} = St) ->
    MRef = erlang:monitor(process, Pid),
    case lists:keymember(Pid,1,Subs) of
	true ->
	    {reply, ok, St};
	false ->
	    Subs1 = [{Pid, MRef} | Subs],
	    {reply, ok, St#state{subscribers = Subs1}}
    end;
handle_call(end_subscription, {Pid,_}, #state{subscribers = Subs} = St) ->
    case lists:keyfind(Pid, 1, Subs) of
	false ->
	    {reply, ok, St};
	{_, MRef} = Found ->
	    erlang:demonitor(MRef),
	    {reply, ok, St#state{subscribers = Subs -- [Found]}}
    end.


handle_info({?MODULE, update}, #state{modified = IsModified} = S) ->
    case IsModified of
	true ->
	    {noreply, report_global(
			report_local(S#state{modified = false}))};
	false ->
	    {noreply, S}
    end;
handle_info({'DOWN', MRef, _, _, _}, #state{subscribers = Subs} = St) ->
    {noreply, St#state{subscribers = lists:keydelete(MRef,2,Subs)}};
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
    {noreply, report_local(S#state{remote_modifiers = NewDs})}.


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
    try M:sample(Timestamp, ModS) of
	{Res, NewModS} ->
	    add_to_history(Res, Timestamp,
			   Sampler#sampler{mod_state = NewModS});
	ignore ->
	    Sampler
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


report_local(#state{modifiers = Local, remote_modifiers = Remote,
		     subscribers = Subs} = S) ->
    Grouped = group_modifiers(Local, Remote),
    jobs_server:set_modifiers(Grouped),
    [Pid ! {jobs_indicators, Grouped} || {Pid,_} <- Subs],
    S.

report_global(#state{modifiers = Local} = S) ->
    gen_server:abcast(nodes(), ?MODULE, {remote, node(), Local}),
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
	  end, {orddict:new(), false}, Samplers),
    FinalMods = orddict:merge(fun(_,V,_) -> V end,Modifiers1,Modifiers0),
    S#state{samplers = Samplers1, modifiers = FinalMods, modified = IsModified}.


merge_modifiers(New, Modifiers) ->
    orddict:merge(
      fun(_, V1, V2) -> erlang:max(V1, V2) end, New, Modifiers).


tell_node(Node, S) ->
    gen_server:cast({?MODULE, Node}, {remote, node(), S#state.modifiers}).


%% example: type = time , step = {seconds, [{0,1},{30,2},{45,3},{50,4}]}
%%          type = value, step = [{80,1},{85,2},{90,3},{95,4},{100,5}]

calc(Type, Template, History) ->
    case queue:is_empty(History) of
	true -> 0;
	false -> calc1(Type, Template, History)
    end.

calc1(time, Template, History) ->
    Now = timestamp(),
    {Unit, Steps} = case Template of
			T when is_list(T) ->
			    {msec, T};
			{U, T} ->
			    U1 = if
				     U==sec; U==seconds -> sec;
				     U==ms; msec        -> msec
				 end,
			    {U1, T}
		    end,
    case true_since(History) of
	0 -> 0;
	Since ->
            %% timestamps are in milliseconds
            Time = case Unit of
		       sec  -> (Now - Since) div 1000;
		       msec -> Now - Since
		   end,
            pick_step(Time, Steps)
    end;
calc1(value, Template, History) ->
    {value, {_, Level}} = queue:peek_r(History),
    pick_step(Level, Template).

true_since(Q) ->
    true_since(queue:out_r(Q), 0).

true_since({{value,{_,false}},_}, Since) ->
    Since;
true_since({empty, _}, Since) ->
    Since;
true_since({{value,{T,true}},Q1}, _) ->
    true_since(queue:out_r(Q1), T).


pick_step(Level, Ls) ->
    take_last(fun({L,_}) ->
                      Level >= L
              end, Ls, 0).

take_last(F, [{_,V} = H|T], Last) ->
    case F(H) of
        true  -> take_last(F, T, V);
        false -> Last
    end;
take_last(_, [], Last) ->
    Last.


%% millisecond timestamp, never wraps
timestamp() ->
    jobs_server:timestamp() div 1000.
