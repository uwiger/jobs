

#Module jobs_queue_list#
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)






__Authors:__ : Ulf Wiger ([`ulf.wiger@erlang-solutions.com`](mailto:ulf.wiger@erlang-solutions.com)).
<a name="types"></a>

##Data Types##




###<a name="type-entry">entry()</a>##



<pre>entry() = {<a href="#type-timestamp">timestamp()</a>, <a href="#type-job">job()</a>}</pre>



###<a name="type-info_item">info_item()</a>##



<pre>info_item() = max_time | oldest_job | length</pre>



###<a name="type-job">job()</a>##



<pre>job() = {pid(), reference()}</pre>
<a name="index"></a>

##Function Index##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#all-1">all/1</a></td><td></td></tr><tr><td valign="top"><a href="#delete-1">delete/1</a></td><td></td></tr><tr><td valign="top"><a href="#empty-1">empty/1</a></td><td></td></tr><tr><td valign="top"><a href="#in-3">in/3</a></td><td></td></tr><tr><td valign="top"><a href="#info-2">info/2</a></td><td></td></tr><tr><td valign="top"><a href="#is_empty-1">is_empty/1</a></td><td></td></tr><tr><td valign="top"><a href="#new-2">new/2</a></td><td></td></tr><tr><td valign="top"><a href="#out-2">out/2</a></td><td></td></tr><tr><td valign="top"><a href="#timedout-1">timedout/1</a></td><td></td></tr><tr><td valign="top"><a href="#timedout-2">timedout/2</a></td><td></td></tr></table>


<a name="functions"></a>

##Function Details##

<a name="all-1"></a>

###all/1##




<pre>all(Queue::#queue{}) -> [<a href="#type-entry">entry()</a>]</pre>
<br></br>


<a name="delete-1"></a>

###delete/1##




`delete(Queue) -> any()`

<a name="empty-1"></a>

###empty/1##




`empty(Queue) -> any()`

<a name="in-3"></a>

###in/3##




<pre>in(TS::<a href="#type-timestamp">timestamp()</a>, Job::<a href="#type-job">job()</a>, Queue::#queue{}) -> #queue{}</pre>
<br></br>


<a name="info-2"></a>

###info/2##




<pre>info(X1::<a href="#type-info_item">info_item()</a>, Queue::#queue{}) -> any()</pre>
<br></br>


<a name="is_empty-1"></a>

###is_empty/1##




<pre>is_empty(Queue::#queue{}) -&gt; boolean()</pre>
<br></br>


<a name="new-2"></a>

###new/2##




`new(Options, Q) -> any()`

<a name="out-2"></a>

###out/2##




<pre>out(N::integer(), Queue::#queue{}) -> {[<a href="#type-entry">entry()</a>], #queue{}}</pre>
<br></br>


<a name="timedout-1"></a>

###timedout/1##




<pre>timedout(Queue::#queue{}) -> {[<a href="#type-entry">entry()</a>], #queue{}}</pre>
<br></br>


<a name="timedout-2"></a>

###timedout/2##




`timedout(TO, Queue) -> any()`

