-module(jobs_prod_simple).

-export([init/2,
	 next/3]).

-include("jobs.hrl").

init(F, _Info) when is_function(F, 0) ->
    #stateless{f = F};
init(F, Info) when is_function(F, 2) ->
    #stateful{f = F, st = F(init, Info)};
init({_, F, A} = MFA, _Info) when is_atom(F), is_list(A) ->
    #stateless{f = MFA}.

next(_Opaque, #stateful{f = F, st = St} = P, Info) ->
    case F(St, Info) of
	{F1, St1} when is_function(F1, 0) ->
	    {F1, P#stateful{st = St1}};
	Other ->
	    erlang:error({bad_producer_next, Other})
    end;
next(_Opaque, #stateless{f = F} = P, _Info) ->
    case F of
	{M,Fn,A} ->
	    {fun() -> apply(M, Fn, A) end, P};
	F when is_function(F, 0) ->
	    {F, P}
    end.
