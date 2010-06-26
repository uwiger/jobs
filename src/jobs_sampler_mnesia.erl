-module(jobs_sampler_mnesia).

-export([init/1,
         sample/2,
         handle_msg/3,
         calc/2]).

-record(st, {levels = []}).



init(Opts) ->
    mnesia:subscribe(system),
    Levels = proplists:get_value(levels, Opts, default_levels()),
    {ok, #st{levels = Levels}}.

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
    {jobs_sampler:calc(time, Levels, History), S}.


is_overload() ->
    %% FIX THIS!!!!
    case mnesia_overload_read() of
        [] ->
            false;
        _ ->
            true
    end.

mnesia_overload_read() ->
    %% This function is not present in older mnesia versions
    %% (or currently indeed in /any/ official version.)
    case erlang:function_exported(mnesia_lib,overload_read,0) of
	false ->
            [];
	true ->
	    mnesia_lib:overload_read()
    end.
