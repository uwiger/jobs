-module(jobs_prod_stateful).

-export([init/2,
	 next/4]).
-include("jobs.hrl").


init(F, _Info) when is_function(F, 0) ->
    F;
init({_, F, A} = MFA, _Info) when is_atom(F), is_list(A) ->
    MFA.

next(_Opaque, _TS, F, _Info) ->
    {F, F}.
