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
