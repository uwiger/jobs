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

-module(jobs_app).

-export([start/2, stop/1,
         init/1]).


start(_, _) ->
    supervisor:start_link({local,?MODULE},?MODULE,[]).

stop(_) ->
    ok.


init([]) ->
    {ok, {{rest_for_one,3,10},
          [{jobs_server, {jobs_server,start_link,[]},
            permanent, 3000, worker, [jobs_server]}|
           sampler_spec()]}}.


sampler_spec() ->
    Mod = case application:get_env(sampler) of
              {ok,M} when M =/= undefined -> M;
              _ -> jobs_sampler
          end,
    [{jobs_sampler, {Mod,start_link,[]}, permanent, 3000, worker, [Mod]}].

            
