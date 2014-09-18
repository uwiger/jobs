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

-module(performer).

-export([start/0, stop/0]).
-export([a_test_scenario/0]).
-define(DELAY_BETWEEN_TASKS, 15).
start() ->
    register(?MODULE, spawn(fun run_cpu_stresstests/0)).

stop() ->
    ?MODULE ! stop.

run_cpu_stresstests() ->
    jobs:add_queue(ramirez,
                   [{regulators, [{rate, [{limit, 20},
                                          {modifiers,
                                           [{cpu, 15, {max, 0}}]}]}]}]),
    spawn_cpu_intensive_jobs().
spawn_cpu_intensive_jobs() ->
    receive
        stop ->
            ok
    after ?DELAY_BETWEEN_TASKS ->
            spawn(fun() -> jobs:run(ramirez, fun cpu_intensive_job/0) end),
            performance_logger:increment_counter(jobs_enqueued, 1),
            spawn_cpu_intensive_jobs()
    end.

cpu_intensive_job() ->
    %% TODO insert real CPU-intensive task here.
    %% NOTE that somehow, this seems like enough to crank up the CPU usage.
    timer:sleep(500),
    performance_logger:increment_counter(jobs_done, 1).

queue_frequency() ->
    jobs:queue_info(ramirez, rate_limit).

%% A simple test scenario that should show you the basic feedback reaction to CPU usage.
%% NOTE that you need to start Jobs with following environmental variable setting:
%% samplers <= [{foobar, jobs_sampler_cpu, []}]
%% where 'foobar' can be - as far as I can tell - any atom.
%% NOTE that you need to set 'samplers', not 'sampler' - setting the latter will result in Jobs not working.
a_test_scenario() ->
    performance_logger:set_counter(jobs_enqueued, 0),
    performance_logger:set_counter(jobs_done, 0),
    start(),
    timer:sleep(500),
    performance_logger:start_recording([{jobs_enqueued, "\"Jobs enqueued\"", diff},
                                        {jobs_done, "\"Jobs done\"", diff},
                                        {fun queue_frequency/0, "\"Queue frequency\"", identity}]),
    timer:sleep(12000),
    stop(),
    timer:sleep(16000),
    performance_logger:end_recording(),
    performance_logger:save_recorded_data_to_file("jobs_cpu.dat"),
    ok.
