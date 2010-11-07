Module jobs_server
==================


<h1>Module jobs_server</h1>

* [Function Index](#index)
* [Function Details](#functions)






__Behaviours:__ [`gen_server`](gen_server.md).

__Authors:__ : Ulf Wiger ([`ulf.wiger@erlang-solutions.com`](mailto:ulf.wiger@erlang-solutions.com)).

<h2><a name="index">Function Index</a></h2>



<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#add_counter-2">add_counter/2</a></td><td></td></tr><tr><td valign="top"><a href="#add_group_rate-2">add_group_rate/2</a></td><td></td></tr><tr><td valign="top"><a href="#add_queue-2">add_queue/2</a></td><td></td></tr><tr><td valign="top"><a href="#ask-0">ask/0</a></td><td></td></tr><tr><td valign="top"><a href="#ask-1">ask/1</a></td><td></td></tr><tr><td valign="top"><a href="#code_change-3">code_change/3</a></td><td></td></tr><tr><td valign="top"><a href="#delete_counter-1">delete_counter/1</a></td><td></td></tr><tr><td valign="top"><a href="#delete_group_rate-1">delete_group_rate/1</a></td><td></td></tr><tr><td valign="top"><a href="#delete_queue-1">delete_queue/1</a></td><td></td></tr><tr><td valign="top"><a href="#done-1">done/1</a></td><td></td></tr><tr><td valign="top"><a href="#handle_call-3">handle_call/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_cast-2">handle_cast/2</a></td><td></td></tr><tr><td valign="top"><a href="#handle_info-2">handle_info/2</a></td><td></td></tr><tr><td valign="top"><a href="#info-1">info/1</a></td><td></td></tr><tr><td valign="top"><a href="#init-1">init/1</a></td><td></td></tr><tr><td valign="top"><a href="#modify_counter-2">modify_counter/2</a></td><td></td></tr><tr><td valign="top"><a href="#modify_group_rate-2">modify_group_rate/2</a></td><td></td></tr><tr><td valign="top"><a href="#modify_regulator-4">modify_regulator/4</a></td><td></td></tr><tr><td valign="top"><a href="#queue_info-1">queue_info/1</a></td><td></td></tr><tr><td valign="top"><a href="#queue_info-2">queue_info/2</a></td><td></td></tr><tr><td valign="top"><a href="#run-1">run/1</a></td><td></td></tr><tr><td valign="top"><a href="#run-2">run/2</a></td><td></td></tr><tr><td valign="top"><a href="#set_modifiers-1">set_modifiers/1</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-0">start_link/0</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-1">start_link/1</a></td><td></td></tr><tr><td valign="top"><a href="#terminate-2">terminate/2</a></td><td></td></tr><tr><td valign="top"><a href="#timestamp-0">timestamp/0</a></td><td></td></tr><tr><td valign="top"><a href="#timestamp_to_datetime-1">timestamp_to_datetime/1</a></td><td></td></tr></table>


<a name="functions"></a>


<h2>Function Details</h2>


<a name="add_counter-2"></a>


<h3>add_counter/2</h3>





`add_counter(Name, Options) -> any()`


<a name="add_group_rate-2"></a>


<h3>add_group_rate/2</h3>





`add_group_rate(Name, Options) -> any()`


<a name="add_queue-2"></a>


<h3>add_queue/2</h3>





`add_queue(Name, Options) -> any()`


<a name="ask-0"></a>


<h3>ask/0</h3>





`ask() -> any()`


<a name="ask-1"></a>


<h3>ask/1</h3>





`ask(Type) -> any()`


<a name="code_change-3"></a>


<h3>code_change/3</h3>





`code_change(FromVsn, St, Extra) -> any()`


<a name="delete_counter-1"></a>


<h3>delete_counter/1</h3>





`delete_counter(Name) -> any()`


<a name="delete_group_rate-1"></a>


<h3>delete_group_rate/1</h3>





`delete_group_rate(Name) -> any()`


<a name="delete_queue-1"></a>


<h3>delete_queue/1</h3>





`delete_queue(Name) -> any()`


<a name="done-1"></a>


<h3>done/1</h3>





`done(Opaque) -> any()`


<a name="handle_call-3"></a>


<h3>handle_call/3</h3>





`handle_call(Req, From, S) -> any()`


<a name="handle_cast-2"></a>


<h3>handle_cast/2</h3>





`handle_cast(Msg, St) -> any()`


<a name="handle_info-2"></a>


<h3>handle_info/2</h3>





`handle_info(Msg, St) -> any()`


<a name="info-1"></a>


<h3>info/1</h3>





`info(Item) -> any()`


<a name="init-1"></a>


<h3>init/1</h3>





`init(Opts) -> any()`


<a name="modify_counter-2"></a>


<h3>modify_counter/2</h3>





`modify_counter(Name, Opts) -> any()`


<a name="modify_group_rate-2"></a>


<h3>modify_group_rate/2</h3>





`modify_group_rate(Name, Opts) -> any()`


<a name="modify_regulator-4"></a>


<h3>modify_regulator/4</h3>





`modify_regulator(Type, QName, RegName, Opts) -> any()`


<a name="queue_info-1"></a>


<h3>queue_info/1</h3>





`queue_info(Name) -> any()`


<a name="queue_info-2"></a>


<h3>queue_info/2</h3>





`queue_info(Name, Item) -> any()`


<a name="run-1"></a>


<h3>run/1</h3>





`run(Fun) -> any()`


<a name="run-2"></a>


<h3>run/2</h3>





`run(Type, Fun) -> any()`


<a name="set_modifiers-1"></a>


<h3>set_modifiers/1</h3>





`set_modifiers(Modifiers) -> any()`


<a name="start_link-0"></a>


<h3>start_link/0</h3>





`start_link() -> any()`


<a name="start_link-1"></a>


<h3>start_link/1</h3>





`start_link(Opts0) -> any()`


<a name="terminate-2"></a>


<h3>terminate/2</h3>





`terminate(X1, X2) -> any()`


<a name="timestamp-0"></a>


<h3>timestamp/0</h3>





`timestamp() -> any()`


<a name="timestamp_to_datetime-1"></a>


<h3>timestamp_to_datetime/1</h3>





`timestamp_to_datetime(TS) -> any()`



_Generated by EDoc, Nov 7 2010, 11:27:46._