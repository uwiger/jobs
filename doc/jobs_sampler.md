

# Module jobs_sampler #
* [Function Index](#index)
* [Function Details](#functions)

__This module defines the `jobs_sampler` behaviour.__<br /> Required callback functions: `init/2`, `sample/2`, `handle_msg/3`, `calc/2`.

__Authors:__ : Ulf Wiger ([`ulf@wiger.net`](mailto:ulf@wiger.net)).
<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#behaviour_info-1">behaviour_info/1</a></td><td></td></tr><tr><td valign="top"><a href="#calc-3">calc/3</a></td><td></td></tr><tr><td valign="top"><a href="#code_change-3">code_change/3</a></td><td></td></tr><tr><td valign="top"><a href="#end_subscription-0">end_subscription/0</a></td><td></td></tr><tr><td valign="top"><a href="#handle_call-3">handle_call/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_cast-2">handle_cast/2</a></td><td></td></tr><tr><td valign="top"><a href="#handle_info-2">handle_info/2</a></td><td></td></tr><tr><td valign="top"><a href="#init-1">init/1</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-0">start_link/0</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-1">start_link/1</a></td><td></td></tr><tr><td valign="top"><a href="#subscribe-0">subscribe/0</a></td><td>Subscribes to feedback indicator information.</td></tr><tr><td valign="top"><a href="#tell_sampler-2">tell_sampler/2</a></td><td></td></tr><tr><td valign="top"><a href="#terminate-2">terminate/2</a></td><td></td></tr><tr><td valign="top"><a href="#trigger_sample-0">trigger_sample/0</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="behaviour_info-1"></a>

### behaviour_info/1 ###

`behaviour_info(X1) -> any()`


<a name="calc-3"></a>

### calc/3 ###

`calc(Type, Template, History) -> any()`


<a name="code_change-3"></a>

### code_change/3 ###

`code_change(FromVsn, State, Extra) -> any()`


<a name="end_subscription-0"></a>

### end_subscription/0 ###

`end_subscription() -> any()`


<a name="handle_call-3"></a>

### handle_call/3 ###

`handle_call(X1, From, State) -> any()`


<a name="handle_cast-2"></a>

### handle_cast/2 ###

`handle_cast(X1, S) -> any()`


<a name="handle_info-2"></a>

### handle_info/2 ###

`handle_info(Msg, State) -> any()`


<a name="init-1"></a>

### init/1 ###

`init(Opts) -> any()`


<a name="start_link-0"></a>

### start_link/0 ###

`start_link() -> any()`


<a name="start_link-1"></a>

### start_link/1 ###

`start_link(Opts) -> any()`


<a name="subscribe-0"></a>

### subscribe/0 ###


<pre><code>
subscribe() -&gt; ok
</code></pre>
<br />


Subscribes to feedback indicator information



This function allows a process to receive the same information as the
jobs_server any time the information changes.


The notifications are delivered on the format `{jobs_indicators, Info}`,
where

```

  Info :: [{IndicatorName, LocalValue, Remote}]
   Remote :: [{NodeName, Value}]
```


This information could be used e.g. to aggregate the information and generate
new sampler information (which could be passed to a sampler plugin using
[`tell_sampler/2`](#tell_sampler-2), or to a specific queue using [`jobs:ask_queue/2`](jobs.md#ask_queue-2).

<a name="tell_sampler-2"></a>

### tell_sampler/2 ###

`tell_sampler(P, Msg) -> any()`


<a name="terminate-2"></a>

### terminate/2 ###

`terminate(X1, S) -> any()`


<a name="trigger_sample-0"></a>

### trigger_sample/0 ###

`trigger_sample() -> any()`


