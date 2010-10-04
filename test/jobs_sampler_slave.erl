-module(jobs_sampler_slave).

-behaviour(jobs_sampler).

-export([init/2,
	 sample/2,
	 handle_msg/3,
	 calc/2]).

-define(NOTEST, 1).

init(_Name, {Type, Levels}) ->
    {ok, {Type, Levels}}.


handle_msg({test, log, V}, _T, S) ->
    {log, V, S};
handle_msg(_Msg, _T, S) ->
    {ignore, S}.


sample(_, _S) ->
    ignore.

calc(History, {Type, Levels} = S) ->
    {[{test,jobs_sampler:calc(Type, Levels, History)}], S}.

