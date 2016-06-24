

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
---------

##Scenarios and Corresponding Configuration Examples

####EXAMPLE 1:
* Add counter regulated queue called ___heavy_crunches___ to limit your cpu intensive code executions to no more than 7 at a time

Configuration:

```erlang

{ jobs, [
    { queues, [
        { heavy_crunches, [ { regulators, [{ counter, [{ limit, 7 }] } ] }] }
      ]
    }
  ]
}

```

Anywhere in your code wrap cpu-intensive work in a call to jobs server and-- __voilà!__ --it is counter-regulated:

```erlang

jobs:run( heavy_crunches,fun()->my_cpu_intensive_calculation() end)

```

####EXAMPLE 2:
* Add rate regulated queue called ___http_requests___ to ensure that your http server gets no more than 1000 requests per second.
* Additionally, set the queue size to 10,000 (i.e. to control queue memory consumption)

Configuration:

```erlang

{ jobs, [
      { queues, [
            { http_requests, [ { max_size, 10000},  {regulators, [{ rate, [{limit, 1000}]}]}]}
        ]
      }
  ]
}

```

Wrap your request entry point in a call to jobs server and it will end up being rate-regulated.

```erlang

jobs:run(http_requests,fun()->handle_http_request() end)

```

NOTE: with the config above, once 10,000 requests accumulates in the queue any incoming requests are dropped on the floor.

####EXAMPLE 3:
* HTTP requests will always have a reasonable execution time.  No point in keeping them in the queue past the timeout.

* Let's create ___patient_user_requests___ queue that will keep requests in the queue for up to 10 seconds

```erlang

{ patient_user_requests, [
    { max_time, 10000},
    { regulators, [{rate, [ { limit, 1000 } ] }
  ]
}

```

* Let's create ___impatient_user_requests___ queue that will keep requests in the queue for up to 200 milliseconds.
Additionally, we'll make it a LIFO queue. Unfair, but if we assume that happy/unhappy is a boolean
we're likely to maximize the happy users!

```erlang

{ impatient_user_requests, [
    { max_time, 200},
    { type, lifo},
    { regulators, [{rate, [ { limit, 1000 } ] }
  ]
}

```

NOTE: In order to pace requests from both queues at 1000 per second, use __group_rate__ regulation (EXAMPLE 4)

####EXAMPLE 4:
* Rate regulate http requests from multiple queues

Create __group_rates__ regulator called ___http_request_rate___  and assign it to both _impatient_user_requests_ and _patient_user_requests_

```erlang

{ jobs, [
    { group_rates,[{ http_request_rate, [{limit,1000}] }] },
    { queues, [
        { impatient_user_requests,
            [ {max_time, 200},
              {type, lifo},
              {regulators,[{ group_rate, http_request_rate}]}
            ]
        },
        { patient_user_requests,
            [ {max_time, 10000},
              {regulators,[{ group_rate, http_request_rate}
            ]
        }
      ]
    }
  ]
}

```

####EXAMPLE 5:
* Can't afford to drop http requests on the floor once max_size is reached?
* Implement and use your own queue to persist those unfortunate http requests and serve them eventually

```erlang

 -module(my_persistent_queue).
 -behaviour(jobs_queue).
 -export([  new/2,
            delete/1,
            in/3,
            out/2,
            peek/1,
            info/2,
            all/1]).

 ## implementation
 ...

```

Configuration:

```erlang

{ jobs, [
    { queues, [
        { http_requests, [
            { mod, my_persistent_queue},
            { max_size, 10000 },
            { regulators, [ { rate, [ { limit, 1000 } ] } ] }
          ]
        }
      ]
    }
  ]
}

```

###The use of sampler framework
1. Get a sampler running and sending feedback to the jobs server.
2. Apply its feedback to a regulator limit.

####EXAMPLE 6:
* Adjust rate regulator limit on the fly based on the feedback from __jobs_sampler_cpu__ named ___cpu_feedback___

```erlang

{ jobs, [
    { samplers, [{ cpu_feedback, jobs_sampler_cpu, [] } ] },
    { queues, [
        { http_requests, [
            { regulators,   [ { rate, [ { limit,1000 } ]  },
            { modifiers,    [ { cpu_feedback,  10} ] } %% 10 = % increment by which to modify the limit
          ]
        }
      ]
    }
  ]
}

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
<tr><td><a href="http://github.com/uwiger/jobs/blob/master/doc/jobs.md" class="module">jobs</a></td></tr>
<tr><td><a href="http://github.com/uwiger/jobs/blob/master/doc/jobs_app.md" class="module">jobs_app</a></td></tr>
<tr><td><a href="http://github.com/uwiger/jobs/blob/master/doc/jobs_info.md" class="module">jobs_info</a></td></tr>
<tr><td><a href="http://github.com/uwiger/jobs/blob/master/doc/jobs_lib.md" class="module">jobs_lib</a></td></tr>
<tr><td><a href="http://github.com/uwiger/jobs/blob/master/doc/jobs_prod_simple.md" class="module">jobs_prod_simple</a></td></tr>
<tr><td><a href="http://github.com/uwiger/jobs/blob/master/doc/jobs_queue.md" class="module">jobs_queue</a></td></tr>
<tr><td><a href="http://github.com/uwiger/jobs/blob/master/doc/jobs_queue_list.md" class="module">jobs_queue_list</a></td></tr>
<tr><td><a href="http://github.com/uwiger/jobs/blob/master/doc/jobs_sampler.md" class="module">jobs_sampler</a></td></tr>
<tr><td><a href="http://github.com/uwiger/jobs/blob/master/doc/jobs_sampler_cpu.md" class="module">jobs_sampler_cpu</a></td></tr>
<tr><td><a href="http://github.com/uwiger/jobs/blob/master/doc/jobs_sampler_history.md" class="module">jobs_sampler_history</a></td></tr>
<tr><td><a href="http://github.com/uwiger/jobs/blob/master/doc/jobs_sampler_mnesia.md" class="module">jobs_sampler_mnesia</a></td></tr>
<tr><td><a href="http://github.com/uwiger/jobs/blob/master/doc/jobs_server.md" class="module">jobs_server</a></td></tr>
<tr><td><a href="http://github.com/uwiger/jobs/blob/master/doc/jobs_stateful_simple.md" class="module">jobs_stateful_simple</a></td></tr></table>

