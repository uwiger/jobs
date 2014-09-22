

# jobs - a Job scheduler for load regulation #

Copyright (c) 2014 Ulf Wiger

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

Examples
--------

The following examples are fetched from the EUC 2013 presentation on Jobs.


#### Regulate incoming HTTP requests (e.g. JSON-RPC) ####

```erlang

%% @doc Handle a JSON-RPC request.
handler_session(Arg) ->
    jobs:run(
        rpc_from_web,
        fun() ->
               try
                  yaws_rpc:handler_session(
                    maybe_multipart(Arg),{?MODULE, web_rpc})
               catch
                   error:E ->
                       ...
               end
    end).

```


#### From Riak prototype, using explicit ask/done ####

```erlang

case jobs:ask(riak_kv_fsm) of
  {ok, JobId} ->
    try
      {ok, Pid} = riak_kv_get_fsm_sup:start_get_fsm(...),
      Timeout = recv_timeout(Options),
      wait_for_reqid(ReqId, Timeout)
    after
      jobs:done(JobId)  %% Only needed if process stays alive
    end;
  {error, rejected} ->  %% Overload!
    {error, timeout}
end

```


#### Shell demo - simple rate-limited queue ####

```erlang

2> jobs:add_queue(q, [{standard_rate,1}]).
ok
3> jobs:run(q, fun() -> io:fwrite("job: ~p~n", [time()]) end).
job: {14,37,7}
ok
4> jobs:run(q, fun() -> io:fwrite("job: ~p~n", [time()]) end).
job: {14,37,8}
ok
...
5> jobs:run(q, fun() -> io:fwrite("job: ~p~n", [time()]) end).
job: {14,37,10}
ok
6> jobs:run(q, fun() -> io:fwrite("job: ~p~n", [time()]) end).
job: {14,37,11}
ok

```


#### Shell demo - "stateful" queues ####

```erlang

Eshell V5.9.2 (abort with ^G)
1> application:start(jobs).
ok
2> jobs:add_queue(q,
     [{standard_rate,1},
      {stateful,fun(init,_) -> {0,5};
                   ({call,{size,Sz},_,_},_) -> {reply,ok,{0,Sz}};
                   ({N,Sz},_) -> {N, {(N+1) rem Sz,Sz}}
                end}]).
ok
3> jobs:run(q,fun(Opaque) -> jobs:job_info(Opaque) end).
0
4> jobs:run(q,fun(Opaque) -> jobs:job_info(Opaque) end).
1
5> jobs:run(q,fun(Opaque) -> jobs:job_info(Opaque) end).
2
6> jobs:run(q,fun(Opaque) -> jobs:job_info(Opaque) end).
3
7> jobs:run(q,fun(Opaque) -> jobs:job_info(Opaque) end).
4
8> jobs:run(q,fun(Opaque) -> jobs:job_info(Opaque) end).
0
9> jobs:run(q,fun(Opaque) -> jobs:job_info(Opaque) end).
1
%% Resize the 'pool'
10> jobs:ask_queue(q, {size,3}).
ok
11> jobs:run(q,fun(Opaque) -> jobs:job_info(Opaque) end).
0
12> jobs:run(q,fun(Opaque) -> jobs:job_info(Opaque) end).
1
13> jobs:run(q,fun(Opaque) -> jobs:job_info(Opaque) end).
2
14> jobs:run(q,fun(Opaque) -> jobs:job_info(Opaque) end).
0
...

```


#### Demo - producers ####

```erlang

Eshell V5.9.2 (abort with ^G)
1> application:start(jobs).
ok
2> jobs:add_queue(p,
  [{producer, fun() -> io:fwrite("job: ~p~n",[time()]) end},
   {standard_rate,1}]).
job: {14,33,51}
ok
3> job: {14,33,52}
job: {14,33,53}
job: {14,33,54}
job: {14,33,55}
...

```


#### Demo - passive queues ####

```erlang

2> jobs:add_queue(q,[passive]).
ok
3> Fun = fun() -> io:fwrite("~p starting...~n",[self()]),
3>                Res = jobs:dequeue(q, 3),
3>                io:fwrite("Res = ~p~n", [Res])
3>       end.
#Fun<erl_eval.20.82930912>
4> jobs:add_queue(p, [{standard_counter,3},{producer,Fun}]).
<0.47.0> starting...
<0.48.0> starting...
<0.49.0> starting...
ok
5> jobs:enqueue(q, job1).
Res = [{113214444910647,job1}]
ok
<0.54.0> starting...

```


#### Demo - queue status ####

```erlang

(a@uwair)1> jobs:queue_info(q).
{queue,[{name,q},
        {mod,jobs_queue},
        {type,fifo},
        {group,undefined},
        {regulators,[{rr,[{name,{rate,q,1}},
                          {rate,{rate,[{limit,1},
                          {preset_limit,1},
                          {interval,1.0e3},
                          {modifiers,
                           [{cpu,10},{memory,10}]},
                          {active_modifiers,[]}
                         ]}}]}]},
        {max_time,undefined},
        {max_size,undefined},
        {latest_dispatch,113216378663298},
        {approved,4},
        {queued,0},
        ...,
        {stateful,undefined},
        {st,{st,45079}}]}

```

Prerequisites
-------------
This application requires 'exprecs'.
The 'exprecs' module is part of http://github.com/uwiger/parse_trans

Contribute
----------
For issues, comments or feedback please [create an issue!] [1]
[1]: http://github.com/uwiger/jobs/issues "jobs issues"


## Modules ##


<table width="100%" border="0" summary="list of modules">
<tr><td><a href="jobs.md" class="module">jobs</a></td></tr>
<tr><td><a href="jobs_app.md" class="module">jobs_app</a></td></tr>
<tr><td><a href="jobs_info.md" class="module">jobs_info</a></td></tr>
<tr><td><a href="jobs_lib.md" class="module">jobs_lib</a></td></tr>
<tr><td><a href="jobs_prod_simple.md" class="module">jobs_prod_simple</a></td></tr>
<tr><td><a href="jobs_queue.md" class="module">jobs_queue</a></td></tr>
<tr><td><a href="jobs_queue_list.md" class="module">jobs_queue_list</a></td></tr>
<tr><td><a href="jobs_sampler.md" class="module">jobs_sampler</a></td></tr>
<tr><td><a href="jobs_sampler_cpu.md" class="module">jobs_sampler_cpu</a></td></tr>
<tr><td><a href="jobs_sampler_history.md" class="module">jobs_sampler_history</a></td></tr>
<tr><td><a href="jobs_sampler_mnesia.md" class="module">jobs_sampler_mnesia</a></td></tr>
<tr><td><a href="jobs_server.md" class="module">jobs_server</a></td></tr>
<tr><td><a href="jobs_stateful_simple.md" class="module">jobs_stateful_simple</a></td></tr></table>

