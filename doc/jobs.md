

# Module jobs #
* [Description](#description)
* [Function Index](#index)
* [Function Details](#functions)



This is the public API of the JOBS framework.
__Authors:__ : Ulf Wiger ([`ulf@wiger.net`](mailto:ulf@wiger.net)).
<a name="description"></a>

## Description ##
 <a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#add_counter-2">add_counter/2</a></td><td>Adds a named counter to the load regulator on the current node.</td></tr><tr><td valign="top"><a href="#add_group_rate-2">add_group_rate/2</a></td><td>Adds a group rate regulator to the load regulator on the current node.</td></tr><tr><td valign="top"><a href="#add_queue-2">add_queue/2</a></td><td>Installs a new queue in the load regulator on the current node.</td></tr><tr><td valign="top"><a href="#ask-1">ask/1</a></td><td>Asks permission to run a job of Type.</td></tr><tr><td valign="top"><a href="#ask_queue-2">ask_queue/2</a></td><td>Sends a synchronous request to a specific queue.</td></tr><tr><td valign="top"><a href="#delete_counter-1">delete_counter/1</a></td><td>Deletes a named counter from the load regulator on the current node.</td></tr><tr><td valign="top"><a href="#delete_group_rate-1">delete_group_rate/1</a></td><td></td></tr><tr><td valign="top"><a href="#delete_queue-1">delete_queue/1</a></td><td>Deletes the named queue from the load regulator on the current node.</td></tr><tr><td valign="top"><a href="#dequeue-2">dequeue/2</a></td><td>Extracts up to <code>N</code> items from a passive queue.</td></tr><tr><td valign="top"><a href="#done-1">done/1</a></td><td>Signals completion of an executed task.</td></tr><tr><td valign="top"><a href="#enqueue-2">enqueue/2</a></td><td>Inserts <code>Item` into a passive queue.

Note that this function only works on passive queues. An exception will be
raised if the queue doesn</code>t exist, or isn't passive.</td></tr><tr><td valign="top"><a href="#info-1">info/1</a></td><td></td></tr><tr><td valign="top"><a href="#job_info-1">job_info/1</a></td><td>Retrieves job-specific information from the <code>Opaque</code> data object.</td></tr><tr><td valign="top"><a href="#modify_counter-2">modify_counter/2</a></td><td></td></tr><tr><td valign="top"><a href="#modify_group_rate-2">modify_group_rate/2</a></td><td></td></tr><tr><td valign="top"><a href="#modify_queue-2">modify_queue/2</a></td><td>Modifies queue parameters of existing queue.</td></tr><tr><td valign="top"><a href="#modify_regulator-4">modify_regulator/4</a></td><td></td></tr><tr><td valign="top"><a href="#queue_info-1">queue_info/1</a></td><td></td></tr><tr><td valign="top"><a href="#queue_info-2">queue_info/2</a></td><td></td></tr><tr><td valign="top"><a href="#run-2">run/2</a></td><td>Executes Function() when permission has been granted by job regulator.</td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="add_counter-2"></a>

### add_counter/2 ###


<pre><code>
add_counter(Name, Options) -&gt; ok
</code></pre>
<br />

Adds a named counter to the load regulator on the current node.
Fails if there already is a counter the name `Name`.
<a name="add_group_rate-2"></a>

### add_group_rate/2 ###


<pre><code>
add_group_rate(Name, Options) -&gt; ok
</code></pre>
<br />

Adds a group rate regulator to the load regulator on the current node.
Fails if there is already a group rate regulator of the same name.
<a name="add_queue-2"></a>

### add_queue/2 ###


<pre><code>
add_queue(Name::any(), Options::[{Key, Value}]) -&gt; ok
</code></pre>
<br />


Installs a new queue in the load regulator on the current node.



Valid options are:



* `{regulators, Rs}`, where `Rs` is a list of rate- or counter-based
regulators. Valid regulators listed below. Default: [].



* `{type, Type}` - type of queue. Valid types listed below. Default: `fifo`.



* `{action, Action}` - automatic action to perform for each request.
Valid actions described below. Default: `undefined`.



* `{check_interval, I}` - If specified (in ms), this overrides the interval
derived from any existing rate regulator. Note that regardless of how often
the queue is checked, enough jobs will be dispatched at each interval to
maintain the highest allowed rate possible, but the check interval may
thus affect how many jobs are dispatched at the same time. Normally, this
should not have to be specified.



* `{max_time, T}`, specifies how long (in ms) a job is allowed to wait
in the queue before it is automatically rejected.



* `{max_size, S}`, indicates how many items can be queued before requests
are automatically rejected. Strictly speaking, size is whatever the queue
behavior reports as the size; in the default queue behavior, it is the
number of elements in the queue.



* `{mod, M}`, indicates which queue behavior to use. Default is `jobs_queue`.



In addition, some 'abbreviated' options are supported:



* `{standard_rate, R}` - equivalent to
`[{regulators,[{rate,[{limit,R}, {modifiers,[{cpu,10},{memory,10}]}]}]}]`



* `{standard_counter, C}` - equivalent to
`[{regulators,[{counter,[{limit,C}, {modifiers,[{cpu,10},{memory,10}]}]}]}]`



* `{producer, F}` - equivalent to `{type, {producer, F}}`



* `passive` - equivalent to `{type, {passive, fifo}}`



* `approve | reject` - equivalent to `{action, approve | reject}`



__Regulators__


* `{rate, Opts}` - rate regulator. Valid options are

1. `{limit, Limit}` where `Limit` is the maximum rate (requests/sec)

1. `{modifiers, Mods}`, control feedback-based regulation. See below.

1. `{name, Name}`, optional. The default name for the regulator is
`{rate, QueueName, N}`, where `N` is an index indicating which rate regulator
in the list is referred. Currently, at most one rate regulator is allowed,
so `N` will always be `1`.



* `{counter, Opts}` - counter regulator. Valid options are

1. `{limit, Limit}`, where `Limit` is the number of concurrent jobs
allowed.

1. `{increment, Incr}`, increment per job. Default is `1`.

1. `{modifiers, Mods}`, control feedback-based regulation. See below.




* `{named_counter, Name, Incr}`, use an existing counter, incrementing it
with `Incr` for each job. `Name` can either refer to a named top-level
counter (see [`add_counter/2`](#add_counter-2)), or a queue-specific counter
(these are named `{counter,Qname,N}`, where `N` is an index specifying
their relative position in the regulators list - e.g. first or second
counter).



* `{group_rate, R}`, refers to a top-level group rate `R`.
See [`add_group_rate/2`](#add_group_rate-2).



__Types__



* `fifo | lifo` - these are the types supported by the default queue
behavior. While lifo may sound like an odd choice, it may have benefits
for stochastic traffic with time constraints: there is no point to
'fairness', since requests cannot control their place in the queue, and
choosing the 'freshest' job may increase overall goodness critera.


* `{producer, F}`, the queue is not for incoming requests, but rather
generates jobs. Valid options for `F` are
(for details, see [`jobs_prod_simpe`](jobs_prod_simpe.md)):

1. A fun of arity 0, indicating a stateless producer

1. A fun of arity 2, indicating a stateful producer

1. `{M, F, A}`, indicating a stateless producer

1. `{Mod, Args}` indicating a stateful producer




* `{action, approve | reject}`, specifies an automatic response to every
request. This can be used to either block a queue (`reject`) or set it as
a pass-through ('approve').



__Modifiers__



Jobs supports feedback-based modification of regulators.



The sampler framework sends feedback messages of type
`[{Modifier, Local, Remote::[{node(), Level}]}]`.



Each regulator can specify a list of modifier instructions:



* `{Modifier, Local, Remote}` - `Modifier` can be any label used by the
samplers (see [`jobs_sampler`](jobs_sampler.md)). `Local` and `Remote` indicate
increments in percent by which to reduce the limit of the given regulator.
The `Local` increment is used for feedback info pertaining to the local
node, and the `Remote` increment is used for remote indicators. `Local`
is given as a percentage value (e.g. `10` for `10 %`). The `Remote`
increment is either `{avg, Percent}` or `{max, Percent}`, indicating whether
to respond to the average load of other nodes or to the most loaded node.
The correction from `Local` and the correction from `Remote` are summed
before applying to the regulator limit.



* `{Modifier, Local}` - same as above, but responding only to local
indications, ignoring the load on remote nodes.



* `{Modifier, F::function((Local, Remote) -> integer())}` - the function
`F(Local, Remote)` is applied and expected to return a correction value,
in percentage units.



* `{Modifier, {Module, Function}}` - `Module:Function(Local Remote)`
is applied an expected to return a correction value in percentage units.



For example, if a rate regulator has a limit of `100` and has a modifier,
`{cpu, 10}`, then a feedback message of `{cpu, 2, _Remote}` will reduce
the rate limit by `2*10` percent, i.e. down to `80`.



Note that modifiers are always applied to the _preset_ limit,
not the current limit. Thus, the next round of feedback messages in our
example will be applied to the preset limit of `100`, not the `80` that
resulted from the previous feedback messages. A correction value of `0`
will reset the limit to the preset value.


If there are more than one modifier with the same name, the last one in the
list will be the one used.

<a name="ask-1"></a>

### ask/1 ###


<pre><code>
ask(Type) -&gt; {ok, Opaque} | {error, Reason}
</code></pre>
<br />


Asks permission to run a job of Type. Returns when permission granted.


The simplest way to have jobs regulated is to spawn a request per job.
The process should immediately call this function, and when granted
permission, execute the job, and then terminate.
If for some reason the process needs to remain, to execute more jobs,
it should explicitly call `jobs:done(Opaque)`.
This is not strictly needed when regulation is rate-based, but as the
regulation strategy may change over time, it is the prudent thing to do.
<a name="ask_queue-2"></a>

### ask_queue/2 ###


<pre><code>
ask_queue(QueueName, Request) -&gt; Reply
</code></pre>
<br />


Sends a synchronous request to a specific queue.


This function is mainly intended to be used for back-end processes that act
as custom extensions to the load regulator itself. It should not be used by
regular clients. Sophisticated queue behaviours could export gen_server-like
logic allowing them to respond to synchronous calls, either for special
inspection, or for influencing the queue state.
<a name="delete_counter-1"></a>

### delete_counter/1 ###


<pre><code>
delete_counter(Name) -&gt; boolean()
</code></pre>
<br />

Deletes a named counter from the load regulator on the current node.
Returns `true` if there was in fact such a counter; `false` otherwise.
<a name="delete_group_rate-1"></a>

### delete_group_rate/1 ###

`delete_group_rate(Name) -> any()`


<a name="delete_queue-1"></a>

### delete_queue/1 ###


<pre><code>
delete_queue(Name) -&gt; boolean()
</code></pre>
<br />

Deletes the named queue from the load regulator on the current node.
Returns `true` if there was in fact such a queue; `false` otherwise.
<a name="dequeue-2"></a>

### dequeue/2 ###


<pre><code>
dequeue(Queue, N) -&gt; [{JobID, Item}]
</code></pre>
<br />


Extracts up to `N` items from a passive queue



Note that this function only works on passive queues. An exception will be
raised if the queue doesn't exist, or if it isn't passive.



This function will block until at least one item can be extracted from the
queue (see [`enqueue/2`](#enqueue-2)). No more than `N` items will be extracted.


The items returned are on the form `{JobID, Item}`, where `JobID` is in
the form of a microsecond timestamp
(see [`jobs_lib:timestamp_to_datetime/1`](jobs_lib.md#timestamp_to_datetime-1)), and `Item` is whatever was
provided in [`enqueue/2`](#enqueue-2).
<a name="done-1"></a>

### done/1 ###


<pre><code>
done(Opaque) -&gt; ok
</code></pre>
<br />


Signals completion of an executed task.


This is used when the current process wants to submit more jobs to load
regulation. It is mandatory when performing counter-based regulation
(unless the process terminates after completing the task). It has no
effect if the job type is purely rate-regulated.
<a name="enqueue-2"></a>

### enqueue/2 ###


<pre><code>
enqueue(Queue, Item) -&gt; ok | {error, Reason}
</code></pre>
<br />


Inserts `Item` into a passive queue.

Note that this function only works on passive queues. An exception will be
raised if the queue doesn`t exist, or isn't passive.


Returns `ok` if `Item` was successfully entered into the queue,
`{error, Reason}` otherwise (e.g. if the queue is full).
<a name="info-1"></a>

### info/1 ###

`info(Item) -> any()`


<a name="job_info-1"></a>

### job_info/1 ###


<pre><code>
job_info(X1::Opaque) -&gt; undefined | Info
</code></pre>
<br />


Retrieves job-specific information from the `Opaque` data object.


The queue could choose to return specific information that is passed to a
granted job request. This could be used e.g. for load-balancing strategies.
<a name="modify_counter-2"></a>

### modify_counter/2 ###

`modify_counter(CName, Opts) -> any()`


<a name="modify_group_rate-2"></a>

### modify_group_rate/2 ###

`modify_group_rate(GRName, Opts) -> any()`


<a name="modify_queue-2"></a>

### modify_queue/2 ###


<pre><code>
modify_queue(Name::any(), Options::[{Key, Value}]) -&gt; ok | {error, Reason}
</code></pre>
<br />


Modifies queue parameters of existing queue.


The queue parameters that can be modified are `max_size` and `max_time`.
<a name="modify_regulator-4"></a>

### modify_regulator/4 ###

`modify_regulator(Type, QName, RegName, Opts) -> any()`


<a name="queue_info-1"></a>

### queue_info/1 ###

`queue_info(Name) -> any()`


<a name="queue_info-2"></a>

### queue_info/2 ###

`queue_info(Name, Item) -> any()`


<a name="run-2"></a>

### run/2 ###


<pre><code>
run(Queue::Type, Function::function()) -&gt; Result
</code></pre>
<br />


Executes Function() when permission has been granted by job regulator.


This is equivalent to performing the following sequence:

```

  case jobs:ask(Type) of
     {ok, Opaque} ->
        try Function()
          after
            jobs:done(Opaque)
        end;
     {error, Reason} ->
        erlang:error(Reason)
  end.
```

