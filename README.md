

#jobs - a Job scheduler for load regulation#


Copyright (c) 2010 Erlang Solutions Ltd.

__Version:__ 0.1



JOBS
====



Jobs is a job scheduler for load regulation of Erlang applications.
It provides a queueing framework where each queue can be configured
for throughput rate, credit pool and feedback compensation.
Queues can be added and modified at runtime, and customizable 
"samplers" propagate load status across all nodes in the system.



Specifically, jobs provides three features:



* Job scheduling: A job is scheduled according to certain constraints.  
For instance, you may want to define that no more than 9 jobs of a  
certain type can execute simultaneously and the maximal rate at  
which you can start such jobs are 300 per second.
* Job queueing: When load is higher than the scheduling limits  
additional jobs are *queued* by the system to be run later when load  
clears. Certain rules govern queues: are they dequeued in FIFO or  
LIFO order? How many jobs can the queue take before it is full? Is  
there a deadline after which jobs should be rejected. When we hit  
the queue limits we reject the job. This provides a feedback  
mechanism on the client of the queue so you can take action.  
* Sampling and dampening: Periodic samples of the Erlang VM can  
provide information about the health of the system in general. If we  
have high CPU load or high memory usage, we apply dampening to the  
scheduling rules: we may lower the concurrency count or the rate at  
which we execute jobs. When the health problem clears, we remove the  
dampener and run at full speed again.



Quickstart
----------

Compile and start a shell:

    $ rebar get-deps
    $ rebar compile
    $ erl -pa ebin/ -pa deps/*/ebin -boot start_sasl

Start the ````jobs```` application:

    1> application:start(jobs).

Paste an example from below into the shell.

### A queue that only allows 3 jobs to run concurrently

    jobs:add_queue(three_at_once, [
        {regulators, [{counter, [
                        {name, three_at_once},
                        {limit, 3}
                      ]}]}
    ]). 
    Task = fun(N) ->
        io:format("Task ~p started\n", [N]),
        timer:sleep(2000),
        io:format("Task ~p finished, took 2 seconds.\n", [N])
    end,
    lists:foreach(fun(N) ->
        spawn( fun() ->
            jobs:run(three_at_once, fun() -> Task(N) end)
        end)        
    end, lists:seq(1,10)).

#### To change the queue from 3-at-once to 2-at-once:

    jobs:modify_counter(three_at_once, [{limit,2}]).

### A queue that starts 3 jobs per second, regardless of job duration

    jobs:add_queue(three_per_sec, [
        {regulators, [{rate, [
                        {name, three_per_sec},
                        {limit, 3}
                     ]}]}
    ]). 
    Task = fun(N) ->
        io:format("Task ~p started\n", [N]),
        timer:sleep(2000),
        io:format("Task ~p finished, took 2 seconds.\n", [N])
    end,
    lists:foreach(fun(N) ->
        spawn( fun() ->
            jobs:run(three_per_sec, fun() -> Task(N) end)
        end)        
    end, lists:seq(1,10)).


#### To change the queue from 3 jobs/sec to 2 jobs/sec:

    jobs:modify_regulator(rate, three_per_sec, three_per_sec, [{limit, 2}]).

Prerequisites
-------------
This application requires 'exprecs'.
The 'exprecs' module is part of http://github.com/esl/parse_trans



Contribute
----------
For issues, comments or feedback please [create an issue!] [1]

[1]: http://github.com/esl/jobs/issues "jobs issues"


##Modules##


<table width="100%" border="0" summary="list of modules">
<tr><td><a href="http://github.com/esl/jobs/blob/master/doc/jobs.md" class="module">jobs</a></td></tr>
<tr><td><a href="http://github.com/esl/jobs/blob/master/doc/jobs_app.md" class="module">jobs_app</a></td></tr>
<tr><td><a href="http://github.com/esl/jobs/blob/master/doc/jobs_info.md" class="module">jobs_info</a></td></tr>
<tr><td><a href="http://github.com/esl/jobs/blob/master/doc/jobs_lib.md" class="module">jobs_lib</a></td></tr>
<tr><td><a href="http://github.com/esl/jobs/blob/master/doc/jobs_queue.md" class="module">jobs_queue</a></td></tr>
<tr><td><a href="http://github.com/esl/jobs/blob/master/doc/jobs_queue_list.md" class="module">jobs_queue_list</a></td></tr>
<tr><td><a href="http://github.com/esl/jobs/blob/master/doc/jobs_sampler.md" class="module">jobs_sampler</a></td></tr>
<tr><td><a href="http://github.com/esl/jobs/blob/master/doc/jobs_sampler_cpu.md" class="module">jobs_sampler_cpu</a></td></tr>
<tr><td><a href="http://github.com/esl/jobs/blob/master/doc/jobs_sampler_history.md" class="module">jobs_sampler_history</a></td></tr>
<tr><td><a href="http://github.com/esl/jobs/blob/master/doc/jobs_sampler_mnesia.md" class="module">jobs_sampler_mnesia</a></td></tr>
<tr><td><a href="http://github.com/esl/jobs/blob/master/doc/jobs_server.md" class="module">jobs_server</a></td></tr></table>

