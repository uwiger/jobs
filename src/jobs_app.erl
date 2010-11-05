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

%% @doc Application module for JOBS.
%% Normally, JOBS is configured at startup, using a static configuration.
%% There is a reconfiguration API {@link jobs}, which is mainly for evolution
%% of the system.
%% 
%% == Configuring JOBS ==
%% A static configuration can be provided via application environment
%% variables for the `jobs' application. The following is a list of 
%% recognised configuration parameters.
%%
%% === {config, Filename} ===
%% Evaluate a file using {@link //kernel/file:script/1}, treating the data
%% returned from the script as a list of configuration options.
%%
%% === {queues, QueueOptions} ===
%% Configure a list of queues according to the provided QueueOptions.
%% If no queues are specified, a queue named `default' will be created
%% with default characteristics.
%%
%% Below are the different queue configuration options:
%%
%% ==== {Name, Options} ====
%% This is the generic queue configuration pattern.
%% `Name :: any()' is used to identify the queue.
%%
%% Options:
%%
%% `{mod, Module::atom()}' provides the name of the queueing module.
%% The default module is `jobs_queue'.
%%
%% `{type, fifo | lifo | {producer, F}}' specifies the semantics of the 
%% queue. Note that the specified queue module may be limited to only one 
%% type (e.g. the `jobs_queue_list' module only supports `lifo' semantics).
%% If the type is `{producer, F}', 
%%
%% `{max_time, integer() | undefined}' specifies the longest time that a job
%% request may spend in the queue. If `undefined', no limit is imposed.
%%
%% `{max_size, integer() | undefined}' specifies the maximum length (number 
%% of job requests) of the queue. If the queue has reached the maximum length,
%% subsequent job requests will be rejected unless it is possible to remove 
%% enough requests that have exceeded the maximum allowed time in the queue.
%%
%% `'
%%
%% ==== {Name, standard_rate, R} ====
%% A simple rate-regulated queue with throughput rate `R', and basic cpu- and
%% memory-related feedback compensation.
%%
%% ==== {Name, standard_counter, N} ====
%% A simple counter-regulated queue, giving each job a weight of 1, and thus
%% allowing at most `N' jobs to execute concurrently. Basic cpu- and memory-
%% related feedback compensation.
%%
%% ==== {Name, producer, F, Options} ====
%% A producer queue is not open for incoming jobs, but will rather initiate
%% jobs at the given rate.
%% @end
%%
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

            
