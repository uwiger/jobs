-module(jobs_stateful_simple).

-export([init/2,
	 next/3,
	 handle_call/4]).

-include("jobs.hrl").

init(F, Info) when is_function(F, 2) ->
    #stateful{f = F, st = F(init, Info)}.

next(_Opaque, #stateful{f = F, st = St} = P, Info) ->
    case F(St, Info) of
	{V, St1} ->
	    {V, P#stateful{st = St1}};
	Other ->
	    erlang:error({bad_stateful_next, Other})
    end.

handle_call(Req, From, #stateful{f = F, st = St} = P, Info) ->
    case F({call, Req, From, St}, Info) of
	{reply, Reply, St1} ->
	    {reply, Reply, P#stateful{st = St1}};
	{noreply, St1} ->
	    {noreply, P#stateful{st = St1}}
    end.
