

# Module jobs_app #
* [Description](#description)
* [Function Index](#index)
* [Function Details](#functions)


Application module for JOBS.

<a name="description"></a>

## Description ##

  Normally, JOBS is configured at startup, using a static configuration.
There is a reconfiguration API [`jobs`](jobs.md), which is mainly for evolution
of the system.




### <a name="Configuring_JOBS">Configuring JOBS</a> ###


A static configuration can be provided via application environment
variables for the `jobs` application. The following is a list of
recognised configuration parameters.




#### <a name="{config,_Filename}">{config, Filename}</a> ####


Evaluate a file using [`//kernel/file:script/1`](/Users/uwiger/uw/me/kernel/doc/file.md#script-1), treating the data
returned from the script as a list of configuration options.




#### <a name="{queues,_QueueOptions}">{queues, QueueOptions}</a> ####


Configure a list of queues according to the provided QueueOptions.
If no queues are specified, a queue named `default` will be created
with default characteristics.



Below are the different queue configuration options:



<h5><a name="{Name,_Options}">{Name, Options}</a></h5>


This is the generic queue configuration pattern.
`Name :: any()` is used to identify the queue.



Options:



`{mod, Module::atom()}` provides the name of the queueing module.
The default module is `jobs_queue`.



`{type, fifo | lifo | approve | reject | {producer, F}}`
specifies the semantics of the queue. Note that the specified queue module
may be limited to only one type (e.g. the `jobs_queue_list` module only
supports `lifo` semantics).



If the type is `{producer, F}`, it doesn't matter which queue module is
used, as it is not possible to submit job requests to a producer queue.
The producer queue will initiate jobs using `spawn_monitor(F)` at the
rate given by the regulators for the queue.



If the type is `approve` or `reject`, respectively, all other options will
be irrelevant. Any request to the queue will either be immediately approved
or immediately rejected.



`{max_time, integer() | undefined}` specifies the longest time that a job
request may spend in the queue. If `undefined`, no limit is imposed.



`{max_size, integer() | undefined}` specifies the maximum length (number
of job requests) of the queue. If the queue has reached the maximum length,
subsequent job requests will be rejected unless it is possible to remove
enough requests that have exceeded the maximum allowed time in the queue.



`{regulators, [{regulator_type(), Opts]}` specifies the regulation
characteristics of the queue.



The following types of regulator are supported:



`regulator_type() :: rate | counter | group_rate`



It is possible to combine different types of regulator on the same queue,
e.g. a queue may have both rate- and counter regulation. It is not possible
to have two different rate regulators for the same queue.



Common regulator options:



`{name, term()}` names the regulator; by default, a name will be generated.



`{limit, integer()}` defines the limit for the regulator. If it is a rate
regulator, the value represents the maximum number of jobs/second; if it
is a counter regulator, it represents the total number of "credits"
available.



`{modifiers, [modifier()]}`



```

  modifier() :: {IndicatorName :: any(), unit()}
                | {Indicator, local_unit(), remote_unit()}
                | {Indicator, Fun}
  local_unit() :: unit() :: integer()
  remote_unit() :: {avg, unit()} | {max, unit()}
```



Feedback indicators are sent from the sampler framework. Each indicator
has the format `{IndicatorName, LocalLoadFactor, Remote}`.



`Remote :: [{Node, LoadFactor}]`



`IndicatorName` defines the type of indicator. It could be e.g. `cpu`,
`memory`, `mnesia`, or any other name defined by one of the sampler plugins.



The effect of a modifier is calculated as the sum of the effects from local
and remote load. As the remote load is represented as a list of
`{Node,Factor}` it is possible to multiply either the average or the max
load on the remote nodes with the given factor: `{avg,Unit} | {max, Unit}`.



For custom interpretation of the feedback indicator, it is possible to
specify a function `F(LocalFactor, Remote) -> Effect`, where Effect is a
positive integer.



The resulting effect value is used to reduce the predefined regulator limit
with the given number of percentage points, e.g. if a rate regulator has
a predefined limit of 100 jobs/sec, and `Effect = 20`, the current rate
limit will become 80 jobs/sec.



`{rate, Opts}` - rate regulation



Currently, no special options exist for rate regulators.



`{counter, Opts}` - counter regulation



The option `{increment, I}` can be used to specify how much of the credit
pool should be assigned to each job. The default increment is 1.



`{named_counter, Name, Increment}` reuses an existing counter regulator.
This can be used to link multiple queues to a shared credit pool. Note that
this does not use the existing counter regulator as a template, but actually
shares the credits with any other queues using the same named counter.



__NOTE__ Currently, if there is no counter corresponding to the alias,
the entry will simply be ignored during regulation. It is likely that this
behaviour will change in the future.



<h5><a name="{Name,_standard_rate,_R}">{Name, standard_rate, R}</a></h5>


A simple rate-regulated queue with throughput rate `R`, and basic cpu- and
memory-related feedback compensation.



<h5><a name="{Name,_standard_counter,_N}">{Name, standard_counter, N}</a></h5>


A simple counter-regulated queue, giving each job a weight of 1, and thus
allowing at most `N` jobs to execute concurrently. Basic cpu- and memory-
related feedback compensation.



<h5><a name="{Name,_producer,_F,_Options}">{Name, producer, F, Options}</a></h5>

A producer queue is not open for incoming jobs, but will rather initiate
jobs at the given rate.<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#init-1">init/1</a></td><td></td></tr><tr><td valign="top"><a href="#start-2">start/2</a></td><td></td></tr><tr><td valign="top"><a href="#stop-1">stop/1</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="init-1"></a>

### init/1 ###

`init(X1) -> any()`


<a name="start-2"></a>

### start/2 ###

`start(X1, X2) -> any()`


<a name="stop-1"></a>

### stop/1 ###

`stop(X1) -> any()`


