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
%% `{type, fifo | lifo | approve | reject | {producer, F}}'
%% specifies the semantics of the queue. Note that the specified queue module
%% may be limited to only one type (e.g. the `jobs_queue_list' module only
%% supports `lifo' semantics).
%%
%% If the type is `{producer, F}', it doesn't matter which queue module is
%% used, as it is not possible to submit job requests to a producer queue.
%% The producer queue will initiate jobs using `spawn_monitor(F)' at the
%% rate given by the regulators for the queue.
%%
%% If the type is `approve' or `reject', respectively, all other options will
%% be irrelevant. Any request to the queue will either be immediately approved
%% or immediately rejected.
%%
%% `{max_time, integer() | undefined}' specifies the longest time that a job
%% request may spend in the queue. If `undefined', no limit is imposed.
%%
%% `{max_size, integer() | undefined}' specifies the maximum length (number
%% of job requests) of the queue. If the queue has reached the maximum length,
%% subsequent job requests will be rejected unless it is possible to remove
%% enough requests that have exceeded the maximum allowed time in the queue.
%%
%% `{regulators, [{regulator_type(), Opts]}' specifies the regulation
%% characteristics of the queue.
%%
%% The following types of regulator are supported:
%%
%% `regulator_type() :: rate | counter | group_rate'
%%
%% It is possible to combine different types of regulator on the same queue,
%% e.g. a queue may have both rate- and counter regulation. It is not possible
%% to have two different rate regulators for the same queue.
%%
%% Common regulator options:
%%
%% `{name, term()}' names the regulator; by default, a name will be generated.
%%
%% `{limit, integer()}' defines the limit for the regulator. If it is a rate
%% regulator, the value represents the maximum number of jobs/second; if it
%% is a counter regulator, it represents the total number of "credits"
%% available.
%%
%% `{modifiers, [modifier()]}'
%%
%% <pre>
%% modifier() :: {IndicatorName :: any(), unit()}
%%               | {Indicator, local_unit(), remote_unit()}
%%               | {Indicator, Fun}
%%
%% local_unit() :: unit() :: integer()
%% remote_unit() :: {avg, unit()} | {max, unit()}
%% </pre>
%%
%% Feedback indicators are sent from the sampler framework. Each indicator
%% has the format `{IndicatorName, LocalLoadFactor, Remote}'.
%%
%% `Remote :: [{Node, LoadFactor}]'
%%
%% `IndicatorName' defines the type of indicator. It could be e.g. `cpu',
%% `memory', `mnesia', or any other name defined by one of the sampler plugins.
%%
%% The effect of a modifier is calculated as the sum of the effects from local
%% and remote load. As the remote load is represented as a list of
%% `{Node,Factor}' it is possible to multiply either the average or the max
%% load on the remote nodes with the given factor: `{avg,Unit} | {max, Unit}'.
%%
%% For custom interpretation of the feedback indicator, it is possible to
%% specify a function `F(LocalFactor, Remote) -> Effect', where Effect is a
%% positive integer.
%%
%% The resulting effect value is used to reduce the predefined regulator limit
%% with the given number of percentage points, e.g. if a rate regulator has
%% a predefined limit of 100 jobs/sec, and `Effect = 20', the current rate
%% limit will become 80 jobs/sec.
%%
%% `{rate, Opts}' - rate regulation
%%
%% Currently, no special options exist for rate regulators.
%%
%% `{counter, Opts}' - counter regulation
%%
%% The option `{increment, I}' can be used to specify how much of the credit
%% pool should be assigned to each job. The default increment is 1.
%%
%% `{named_counter, Name, Increment}' reuses an existing counter regulator.
%% This can be used to link multiple queues to a shared credit pool. Note that
%% this does not use the existing counter regulator as a template, but actually
%% shares the credits with any other queues using the same named counter.
%%
%% __NOTE__ Currently, if there is no counter corresponding to the alias,
%% the entry will simply be ignored during regulation. It is likely that this
%% behaviour will change in the future.
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
