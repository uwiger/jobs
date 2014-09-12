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

-module(jobs_sampler_mnesia).

-behaviour(jobs_sampler).

-export([init/2,
         sample/2,
         handle_msg/3,
         calc/2]).

-record(st, {levels = [],
	     subscriber}).



init(Name, Opts) ->
    Pid = spawn_link(fun() ->
			     mnesia:subscribe(system),
			     subscriber_loop(Name)
		     end),
    Levels = proplists:get_value(levels, Opts, default_levels()),
    {ok, #st{levels = Levels, subscriber = Pid}}.

default_levels() ->
    {seconds, [{0,1}, {30,2}, {45,3}, {60,4}]}.

handle_msg({mnesia_system_event, {mnesia,{dump_log,_}}}, _T, S) ->
    {log, true, S};
handle_msg({mnesia_system_event, {mnesia_tm, message_queue_len, _}}, _T, S) ->
    {log, true, S};
handle_msg(_, _T, S) ->
    {ignore, S}.

sample(_T, S) ->
    {is_overload(), S}.

calc(History, #st{levels = Levels} = S) ->
    {[{mnesia,jobs_sampler:calc(time, Levels, History)}], S}.


subscriber_loop(Name) ->
    receive
	Msg ->
	    case jobs_sampler:tell_sampler(Name, Msg) of
		ok ->
		    subscriber_loop(Name);
		{error, _} ->
		    %% sampler likely removed
		    exit(normal)
	    end
    end.


is_overload() ->
    %% e.g: [{mnesia_tm,true},{mnesia_dump_log,false}]
    lists:keymember(true, 2, mnesia_overload_read()).

mnesia_overload_read() ->
    %% This function is not present in mnesia versions older than R14A
    case erlang:function_exported(mnesia_lib,overload_read,0) of
	false ->
            [];
	true ->
	    mnesia_lib:overload_read()
    end.
