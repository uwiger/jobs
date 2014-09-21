

# Module jobs_queue #
* [Description](#description)
* [Function Index](#index)
* [Function Details](#functions)


Default queue behaviour for JOBS (using ordered_set ets).
__This module defines the `jobs_queue` behaviour.__<br /> Required callback functions: `new/2`, `delete/1`, `in/3`, `peek/1`, `out/2`, `all/1`, `info/2`.

__Authors:__ : Ulf Wiger ([`ulf@wiger.net`](mailto:ulf@wiger.net)).
<a name="description"></a>

## Description ##


This module implements the default queue behaviour for JOBS, and also
specifies the behaviour itself.<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#all-1">all/1</a></td><td>Return all the job entries in the queue, not removing them from the queue.</td></tr><tr><td valign="top"><a href="#behaviour_info-1">behaviour_info/1</a></td><td></td></tr><tr><td valign="top"><a href="#delete-1">delete/1</a></td><td>Queue is being deleted; remove any external data structures.</td></tr><tr><td valign="top"><a href="#empty-1">empty/1</a></td><td></td></tr><tr><td valign="top"><a href="#in-3">in/3</a></td><td>Enqueue a job reference; return the updated queue.</td></tr><tr><td valign="top"><a href="#info-2">info/2</a></td><td>Return information about the queue.</td></tr><tr><td valign="top"><a href="#is_empty-1">is_empty/1</a></td><td></td></tr><tr><td valign="top"><a href="#new-2">new/2</a></td><td>Instantiate a new queue.</td></tr><tr><td valign="top"><a href="#out-2">out/2</a></td><td>Dequeue a batch of N jobs; return the modified queue.</td></tr><tr><td valign="top"><a href="#peek-1">peek/1</a></td><td>Looks at the first item in the queue, without removing it.</td></tr><tr><td valign="top"><a href="#representation-1">representation/1</a></td><td>A representation of a queue which can be inspected.</td></tr><tr><td valign="top"><a href="#timedout-1">timedout/1</a></td><td>Return all entries that have been in the queue longer than MaxTime.</td></tr><tr><td valign="top"><a href="#timedout-2">timedout/2</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="all-1"></a>

### all/1 ###


<pre><code>
all(Queue::#queue{}) -&gt; [JobEntry]
</code></pre>
<br />

Return all the job entries in the queue, not removing them from the queue.

<a name="behaviour_info-1"></a>

### behaviour_info/1 ###

`behaviour_info(X1) -> any()`


<a name="delete-1"></a>

### delete/1 ###


<pre><code>
delete(Queue::#queue{}) -&gt; any()
</code></pre>
<br />


Queue is being deleted; remove any external data structures.


If the queue behaviour has created an ETS table or similar, this is the place
to get rid of it.
<a name="empty-1"></a>

### empty/1 ###

`empty(Queue) -> any()`


<a name="in-3"></a>

### in/3 ###


<pre><code>
in(TS::Timestamp, Job, Queue::#queue{}) -&gt; #queue{}
</code></pre>
<br />


Enqueue a job reference; return the updated queue.


This puts a job into the queue. The callback function is responsible for
updating the #queue.oldest_job attribute, if needed. The #queue.oldest_job
attribute shall either contain the Timestamp of the oldest job in the queue,
or `undefined` if the queue is empty. It may be noted that, especially in the
fairly trivial case of the `in/3` function, the oldest job would be
`erlang:min(Timestamp, PreviousOldest)`, even if `PreviousOldest == undefined`.
<a name="info-2"></a>

### info/2 ###


<pre><code>
info(X1::Item, Queue::#queue{}) -&gt; Info
</code></pre>

<ul class="definitions"><li><code>Item = max_time | oldest_job | length</code></li></ul>

Return information about the queue.

<a name="is_empty-1"></a>

### is_empty/1 ###


<pre><code>
is_empty(Queue::#queue{}) -&gt; boolean()
</code></pre>
<br />


<a name="new-2"></a>

### new/2 ###


<pre><code>
new(Options, Q::#queue{}) -&gt; #queue{}
</code></pre>
<br />


Instantiate a new queue.


Options is the list of options provided when defining the queue.
Q is an initial #queue{} record. It can be used directly by including
`jobs/include/jobs.hrl`, or by using exprecs-style record accessors in the
module `jobs_info`.
See [parse_trans](http://github.com/uwiger/parse_trans) for more info
on exprecs. In the `new/2` function, the #queue.st attribute will normally be
used to keep track of the queue data structure.
<a name="out-2"></a>

### out/2 ###


<pre><code>
out(N::integer(), Queue::#queue{}) -&gt; {[Entry], #queue{}}
</code></pre>
<br />


Dequeue a batch of N jobs; return the modified queue.


Note that this function may need to update the #queue.oldest_job attribute,
especially if the queue becomes empty.
<a name="peek-1"></a>

### peek/1 ###


<pre><code>
peek(Queue::#queue{}) -&gt; JobEntry | undefined
</code></pre>
<br />

Looks at the first item in the queue, without removing it.

<a name="representation-1"></a>

### representation/1 ###

`representation(Queue) -> any()`

A representation of a queue which can be inspected
<a name="timedout-1"></a>

### timedout/1 ###


<pre><code>
timedout(Queue::#queue{}) -&gt; [] | {[Entry], #queue{}}
</code></pre>
<br />


Return all entries that have been in the queue longer than MaxTime.


NOTE: This is an inspection function; it doesn't remove the job entries.
<a name="timedout-2"></a>

### timedout/2 ###

`timedout(TO, Queue) -> any()`


