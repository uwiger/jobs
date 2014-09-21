

# Module jobs_queue_list #
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

__Authors:__ : Ulf Wiger ([`ulf@wiger.net`](mailto:ulf@wiger.net)).

<a name="types"></a>

## Data Types ##




### <a name="type-entry">entry()</a> ###



<pre><code>
entry() = {<a href="#type-timestamp">timestamp()</a>, <a href="#type-job">job()</a>}
</code></pre>





### <a name="type-info_item">info_item()</a> ###



<pre><code>
info_item() = max_time | oldest_job | length
</code></pre>





### <a name="type-job">job()</a> ###



<pre><code>
job() = {pid(), reference()}
</code></pre>


<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#all-1">all/1</a></td><td></td></tr><tr><td valign="top"><a href="#delete-1">delete/1</a></td><td></td></tr><tr><td valign="top"><a href="#empty-1">empty/1</a></td><td></td></tr><tr><td valign="top"><a href="#in-3">in/3</a></td><td></td></tr><tr><td valign="top"><a href="#info-2">info/2</a></td><td></td></tr><tr><td valign="top"><a href="#is_empty-1">is_empty/1</a></td><td></td></tr><tr><td valign="top"><a href="#new-2">new/2</a></td><td></td></tr><tr><td valign="top"><a href="#out-2">out/2</a></td><td></td></tr><tr><td valign="top"><a href="#peek-1">peek/1</a></td><td></td></tr><tr><td valign="top"><a href="#representation-1">representation/1</a></td><td></td></tr><tr><td valign="top"><a href="#timedout-1">timedout/1</a></td><td></td></tr><tr><td valign="top"><a href="#timedout-2">timedout/2</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="all-1"></a>

### all/1 ###


<pre><code>
all(Queue::#queue{}) -&gt; [<a href="#type-entry">entry()</a>]
</code></pre>
<br />


<a name="delete-1"></a>

### delete/1 ###

`delete(Queue) -> any()`


<a name="empty-1"></a>

### empty/1 ###

`empty(Queue) -> any()`


<a name="in-3"></a>

### in/3 ###


<pre><code>
in(TS::<a href="#type-timestamp">timestamp()</a>, Job::<a href="#type-job">job()</a>, Queue::#queue{}) -&gt; #queue{}
</code></pre>
<br />


<a name="info-2"></a>

### info/2 ###


<pre><code>
info(X1::<a href="#type-info_item">info_item()</a>, Queue::#queue{}) -&gt; any()
</code></pre>
<br />


<a name="is_empty-1"></a>

### is_empty/1 ###


<pre><code>
is_empty(Queue::#queue{}) -&gt; boolean()
</code></pre>
<br />


<a name="new-2"></a>

### new/2 ###

`new(Options, Q) -> any()`


<a name="out-2"></a>

### out/2 ###


<pre><code>
out(N::integer(), Queue::#queue{}) -&gt; {[<a href="#type-entry">entry()</a>], #queue{}}
</code></pre>
<br />


<a name="peek-1"></a>

### peek/1 ###

`peek(Queue) -> any()`


<a name="representation-1"></a>

### representation/1 ###

`representation(Queue) -> any()`


<a name="timedout-1"></a>

### timedout/1 ###


<pre><code>
timedout(Queue::#queue{}) -&gt; {[<a href="#type-entry">entry()</a>], #queue{}}
</code></pre>
<br />


<a name="timedout-2"></a>

### timedout/2 ###

`timedout(TO, Queue) -> any()`


