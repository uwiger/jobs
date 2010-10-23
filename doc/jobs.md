Module jobs
===========


#Module jobs#
* [Description](#description)
* [Function Index](#index)
* [Function Details](#functions)

  This is the public API of the JOBS framework.
__Authors:__ : Ulf Wiger ([`ulf.wiger@erlang-solutions.com`](mailto:ulf.wiger@erlang-solutions.com)).

##<a name="description">Description</a>##

  This is the public API of the JOBS framework.
 

##<a name="index">Function Index</a>##

<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#add_counter-2">add_counter/2</a></td><td>Adds a named counter to the load regulator on the current node.</td></tr><tr><td valign="top"><a href="#add_group_rate-2">add_group_rate/2</a></td><td>Adds a group rate regulator to the load regulator on the current node.</td></tr><tr><td valign="top"><a href="#add_queue-2">add_queue/2</a></td><td>Installs a new queue in the load regulator on the current node.</td></tr><tr><td valign="top"><a href="#ask-1">ask/1</a></td><td>Asks permission to run a job of Type.</td></tr><tr><td valign="top"><a href="#delete_counter-1">delete_counter/1</a></td><td>Deletes a named counter from the load regulator on the current node.</td></tr><tr><td valign="top"><a href="#delete_group_rate-1">delete_group_rate/1</a></td><td></td></tr><tr><td valign="top"><a href="#delete_queue-1">delete_queue/1</a></td><td>Deletes the named queue from the load regulator on the current node.</td></tr><tr><td valign="top"><a href="#done-1">done/1</a></td><td>Signals completion of an executed task.</td></tr><tr><td valign="top"><a href="#info-1">info/1</a></td><td></td></tr><tr><td valign="top"><a href="#modify_counter-2">modify_counter/2</a></td><td></td></tr><tr><td valign="top"><a href="#modify_group_rate-2">modify_group_rate/2</a></td><td></td></tr><tr><td valign="top"><a href="#modify_regulator-4">modify_regulator/4</a></td><td></td></tr><tr><td valign="top"><a href="#queue_info-1">queue_info/1</a></td><td></td></tr><tr><td valign="top"><a href="#queue_info-2">queue_info/2</a></td><td></td></tr><tr><td valign="top"><a href="#run-2">run/2</a></td><td>Executes Function() when permission has been granted by job regulator.</td></tr></table>

<a name="functions"></a>


##Function Details##

<a name="add_counter-2"></a>


###add_counter/2##


`add_counter(Name, Options) -> ok`

Adds a named counter to the load regulator on the current node.
  Fails if there already is a counter the name `Name`.
<a name="add_group_rate-2"></a>


###add_group_rate/2##


`add_group_rate(Name, Options) -> ok`

Adds a group rate regulator to the load regulator on the current node.
  Fails if there is already a group rate regulator of the same name.
<a name="add_queue-2"></a>


###add_queue/2##


`add_queue(Name::any(), Options::[{Key, Value}]) -> ok`

Installs a new queue in the load regulator on the current node.
<a name="ask-1"></a>


###ask/1##


`ask(Type) -> {ok, Opaque} | {error, Reason}`


Asks permission to run a job of Type. Returns when permission granted.
 
  The simplest way to have jobs regulated is to spawn a request per job.
  The process should immediately call this function, and when granted
  permission, execute the job, and then terminate.
  If for some reason the process needs to remain, to execute more jobs,
  it should explicitly call `jobs:done(Opaque)`.
  This is not strictly needed when regulation is rate-based, but as the
  regulation strategy may change over time, it is the prudent thing to do.
<a name="delete_counter-1"></a>


###delete_counter/1##


`delete_counter(Name) -> [boolean()](#type-boolean)`

Deletes a named counter from the load regulator on the current node.
  Returns `true` if there was in fact such a counter; `false` otherwise.
<a name="delete_group_rate-1"></a>


###delete_group_rate/1##


`delete_group_rate(Name) -> any()`

<a name="delete_queue-1"></a>


###delete_queue/1##


`delete_queue(Name) -> [boolean()](#type-boolean)`

Deletes the named queue from the load regulator on the current node.
  Returns `true` if there was in fact such a queue; `false` otherwise.
<a name="done-1"></a>


###done/1##


`done(Opaque) -> ok`


Signals completion of an executed task.
 
  This is used when the current process wants to submit more jobs to load
  regulation. It is mandatory when performing counter-based regulation
  (unless the process terminates after completing the task). It has no
  effect if the job type is purely rate-regulated.
<a name="info-1"></a>


###info/1##


`info(Item) -> any()`

<a name="modify_counter-2"></a>


###modify_counter/2##


`modify_counter(CName, Opts) -> any()`

<a name="modify_group_rate-2"></a>


###modify_group_rate/2##


`modify_group_rate(GRName, Opts) -> any()`

<a name="modify_regulator-4"></a>


###modify_regulator/4##


`modify_regulator(Type, QName, RegName, Opts) -> any()`

<a name="queue_info-1"></a>


###queue_info/1##


`queue_info(Name) -> any()`

<a name="queue_info-2"></a>


###queue_info/2##


`queue_info(Name, Item) -> any()`

<a name="run-2"></a>


###run/2##


`run(Queue::Type, Function::function()) -> Result`


Executes Function() when permission has been granted by job regulator.
 
  This is equivalent to performing the following sequence:
  
<pre>
  case jobs:ask(Type) of
     {ok, Opaque} ->
        try Function()
          after
            jobs:done(Opaque)
        end;
     {error, Reason} ->
        erlang:error(Reason)
  end.
  </pre>

_Generated by EDoc, Oct 23 2010, 22:57:40._