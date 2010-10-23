Module jobs_server
==================


#Module jobs_server#
* [Function Index](#index)
* [Function Details](#functions)

__Behaviours:__ [`gen_server`](gen_server.html).
__Authors:__ : Ulf Wiger ([`ulf.wiger@erlang-solutions.com`](mailto:ulf.wiger@erlang-solutions.com)).

##<a name="index">Function Index</a>##

<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#add_counter-2">add_counter/2</a></td><td></td></tr><tr><td valign="top"><a href="#add_group_rate-2">add_group_rate/2</a></td><td></td></tr><tr><td valign="top"><a href="#add_queue-2">add_queue/2</a></td><td></td></tr><tr><td valign="top"><a href="#ask-0">ask/0</a></td><td></td></tr><tr><td valign="top"><a href="#ask-1">ask/1</a></td><td></td></tr><tr><td valign="top"><a href="#code_change-3">code_change/3</a></td><td></td></tr><tr><td valign="top"><a href="#delete_counter-1">delete_counter/1</a></td><td></td></tr><tr><td valign="top"><a href="#delete_group_rate-1">delete_group_rate/1</a></td><td></td></tr><tr><td valign="top"><a href="#delete_queue-1">delete_queue/1</a></td><td></td></tr><tr><td valign="top"><a href="#done-1">done/1</a></td><td></td></tr><tr><td valign="top"><a href="#handle_call-3">handle_call/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_cast-2">handle_cast/2</a></td><td></td></tr><tr><td valign="top"><a href="#handle_info-2">handle_info/2</a></td><td></td></tr><tr><td valign="top"><a href="#info-1">info/1</a></td><td></td></tr><tr><td valign="top"><a href="#init-1">init/1</a></td><td></td></tr><tr><td valign="top"><a href="#modify_counter-2">modify_counter/2</a></td><td></td></tr><tr><td valign="top"><a href="#modify_group_rate-2">modify_group_rate/2</a></td><td></td></tr><tr><td valign="top"><a href="#modify_regulator-4">modify_regulator/4</a></td><td></td></tr><tr><td valign="top"><a href="#queue_info-1">queue_info/1</a></td><td></td></tr><tr><td valign="top"><a href="#queue_info-2">queue_info/2</a></td><td></td></tr><tr><td valign="top"><a href="#run-1">run/1</a></td><td></td></tr><tr><td valign="top"><a href="#run-2">run/2</a></td><td></td></tr><tr><td valign="top"><a href="#set_modifiers-1">set_modifiers/1</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-0">start_link/0</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-1">start_link/1</a></td><td></td></tr><tr><td valign="top"><a href="#terminate-2">terminate/2</a></td><td></td></tr><tr><td valign="top"><a href="#timestamp-0">timestamp/0</a></td><td></td></tr><tr><td valign="top"><a href="#timestamp_to_datetime-1">timestamp_to_datetime/1</a></td><td></td></tr></table>

<a name="functions"></a>


##Function Details##

<a name="add_counter-2"></a>


###add_counter/2##


`add_counter(Name, Options) -> any()`

<a name="add_group_rate-2"></a>


###add_group_rate/2##


`add_group_rate(Name, Options) -> any()`

<a name="add_queue-2"></a>


###add_queue/2##


`add_queue(Name, Options) -> any()`

<a name="ask-0"></a>


###ask/0##


`ask() -> any()`

<a name="ask-1"></a>


###ask/1##


`ask(Type) -> any()`

<a name="code_change-3"></a>


###code_change/3##


`code_change(FromVsn, St, Extra) -> any()`

<a name="delete_counter-1"></a>


###delete_counter/1##


`delete_counter(Name) -> any()`

<a name="delete_group_rate-1"></a>


###delete_group_rate/1##


`delete_group_rate(Name) -> any()`

<a name="delete_queue-1"></a>


###delete_queue/1##


`delete_queue(Name) -> any()`

<a name="done-1"></a>


###done/1##


`done(Opaque) -> any()`

<a name="handle_call-3"></a>


###handle_call/3##


`handle_call(Req, From, S) -> any()`

<a name="handle_cast-2"></a>


###handle_cast/2##


`handle_cast(Msg, St) -> any()`

<a name="handle_info-2"></a>


###handle_info/2##


`handle_info(Msg, St) -> any()`

<a name="info-1"></a>


###info/1##


`info(Item) -> any()`

<a name="init-1"></a>


###init/1##


`init(Opts) -> any()`

<a name="modify_counter-2"></a>


###modify_counter/2##


`modify_counter(Name, Opts) -> any()`

<a name="modify_group_rate-2"></a>


###modify_group_rate/2##


`modify_group_rate(Name, Opts) -> any()`

<a name="modify_regulator-4"></a>


###modify_regulator/4##


`modify_regulator(Type, QName, RegName, Opts) -> any()`

<a name="queue_info-1"></a>


###queue_info/1##


`queue_info(Name) -> any()`

<a name="queue_info-2"></a>


###queue_info/2##


`queue_info(Name, Item) -> any()`

<a name="run-1"></a>


###run/1##


`run(Fun) -> any()`

<a name="run-2"></a>


###run/2##


`run(Type, Fun) -> any()`

<a name="set_modifiers-1"></a>


###set_modifiers/1##


`set_modifiers(Modifiers) -> any()`

<a name="start_link-0"></a>


###start_link/0##


`start_link() -> any()`

<a name="start_link-1"></a>


###start_link/1##


`start_link(Opts) -> any()`

<a name="terminate-2"></a>


###terminate/2##


`terminate(X1, X2) -> any()`

<a name="timestamp-0"></a>


###timestamp/0##


`timestamp() -> any()`

<a name="timestamp_to_datetime-1"></a>


###timestamp_to_datetime/1##


`timestamp_to_datetime(TS) -> any()`

_Generated by EDoc, Oct 23 2010, 22:57:40._