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
