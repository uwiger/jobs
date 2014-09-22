%%==============================================================================
%% Copyright 2014 Ulf Wiger
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%==============================================================================

%%-------------------------------------------------------------------
%% File    : jobs.erl
%% @author  : Ulf Wiger <ulf@wiger.net>
%% @doc
%% This is the public API of the JOBS framework.
%%
%% @end
%% Created : 15 Jan 2010 by Ulf Wiger <ulf@wiger.net>
%%-------------------------------------------------------------------
-module(jobs).

-export([ask/1,
	 done/1,
	 job_info/1,
	 run/2,
	 enqueue/2,
	 dequeue/2]).

-export([ask_queue/2]).


%% Configuration API
-export([add_queue/2,
	 modify_queue/2,
         delete_queue/1,
         info/1,
         queue_info/1,
	 queue_info/2,
         modify_regulator/4,
         add_counter/2,
         modify_counter/2,
         delete_counter/1,
         add_group_rate/2,
         modify_group_rate/2,
         delete_group_rate/1]).


%% @spec ask(Type) -> {ok, Opaque} | {error, Reason}
%% @doc Asks permission to run a job of Type. Returns when permission granted.
%%
%% The simplest way to have jobs regulated is to spawn a request per job.
%% The process should immediately call this function, and when granted
%% permission, execute the job, and then terminate.
%% If for some reason the process needs to remain, to execute more jobs,
%% it should explicitly call `jobs:done(Opaque)'.
%% This is not strictly needed when regulation is rate-based, but as the
%% regulation strategy may change over time, it is the prudent thing to do.
%% @end
%%
ask(Type) ->
    jobs_server:ask(Type).

%% @spec done(Opaque) -> ok
%% @doc Signals completion of an executed task.
%%
%% This is used when the current process wants to submit more jobs to load
%% regulation. It is mandatory when performing counter-based regulation
%% (unless the process terminates after completing the task). It has no
%% effect if the job type is purely rate-regulated.
%% @end
%%
done(Opaque) ->
    jobs_server:done(Opaque).

%% @spec run(Type, Function::function()) -> Result
%% @doc Executes Function() when permission has been granted by job regulator.
%%
%% This is equivalent to performing the following sequence:
%% <pre>
%% case jobs:ask(Type) of
%%    {ok, Opaque} ->
%%       try Function()
%%         after
%%           jobs:done(Opaque)
%%       end;
%%    {error, Reason} ->
%%       erlang:error(Reason)
%% end.
%% </pre>
%% @end
%%
run(Queue, F) when is_function(F, 0); is_function(F, 1) ->
    jobs_server:run(Queue, F).

%% @spec enqueue(Queue, Item) -> ok | {error, Reason}
%% @doc Inserts `Item` into a passive queue.
%%
%% Note that this function only works on passive queues. An exception will be
%% raised if the queue doesn't exist, or isn't passive.
%%
%% Returns `ok' if `Item' was successfully entered into the queue,
%% `{error, Reason}' otherwise (e.g. if the queue is full).
%% @end
enqueue(Queue, Item) ->
    jobs_server:enqueue(Queue, Item).

%% @spec dequeue(Queue, N) -> [{JobID, Item}]
%% @doc Extracts up to `N' items from a passive queue
%%
%% Note that this function only works on passive queues. An exception will be
%% raised if the queue doesn't exist, or if it isn't passive.
%%
%% This function will block until at least one item can be extracted from the
%% queue (see {@link enqueue/2}). No more than `N' items will be extracted.
%%
%% The items returned are on the form `{JobID, Item}', where `JobID' is in
%% the form of a microsecond timestamp
%% (see {@link jobs_lib:timestamp_to_datetime/1}), and `Item' is whatever was
%% provided in {@link enqueue/2}.
%% @end
dequeue(Queue, N) when N =:= infinity; is_integer(N), N > 0 ->
    jobs_server:dequeue(Queue, N).

%% @spec job_info(Opaque) -> undefined | Info
%% @doc Retrieves job-specific information from the `Opaque' data object.
%%
%% The queue could choose to return specific information that is passed to a
%% granted job request. This could be used e.g. for load-balancing strategies.
%% @end
%%
job_info({_, Opaque}) ->
    proplists:get_value(info, Opaque).

%% @spec add_queue(Name::any(), Options::[{Key,Value}]) -> ok
%% @doc Installs a new queue in the load regulator on the current node.
%%
%% Valid options are:
%%
%% * `{regulators, Rs}', where `Rs' is a list of rate- or counter-based
%% regulators. Valid regulators listed below. Default: [].
%%
%% * `{type, Type}' - type of queue. Valid types listed below. Default: `fifo'.
%%
%% * `{action, Action}' - automatic action to perform for each request.
%% Valid actions described below. Default: `undefined'.
%%
%% * `{check_interval, I}' - If specified (in ms), this overrides the interval
%% derived from any existing rate regulator. Note that regardless of how often
%% the queue is checked, enough jobs will be dispatched at each interval to
%% maintain the highest allowed rate possible, but the check interval may
%% thus affect how many jobs are dispatched at the same time. Normally, this
%% should not have to be specified.
%%
%% * `{max_time, T}', specifies how long (in ms) a job is allowed to wait
%% in the queue before it is automatically rejected.
%%
%% * `{max_size, S}', indicates how many items can be queued before requests
%% are automatically rejected. Strictly speaking, size is whatever the queue
%% behavior reports as the size; in the default queue behavior, it is the
%% number of elements in the queue.
%%
%% * `{mod, M}', indicates which queue behavior to use. Default is `jobs_queue'.
%%
%% In addition, some 'abbreviated' options are supported:
%%
%% * `{standard_rate, R}' - equivalent to
%% `[{regulators,[{rate,[{limit,R}, {modifiers,[{cpu,10},{memory,10}]}]}]}]'
%%
%% * `{standard_counter, C}' - equivalent to
%% `[{regulators,[{counter,[{limit,C}, {modifiers,[{cpu,10},{memory,10}]}]}]}]'
%%
%% * `{producer, F}' - equivalent to `{type, {producer, F}}'
%%
%% * `passive' - equivalent to `{type, {passive, fifo}}'
%%
%% * `approve | reject' - equivalent to `{action, approve | reject}'
%%
%% <b>Regulators</b>
%%
%% * `{rate, Opts}' - rate regulator. Valid options are
%% <ol>
%%  <li>`{limit, Limit}' where `Limit' is the maximum rate (requests/sec)</li>
%% <li>`{modifiers, Mods}', control feedback-based regulation. See below.</li>
%% <li>`{name, Name}', optional. The default name for the regulator is
%% `{rate, QueueName, N}', where `N' is an index indicating which rate regulator
%% in the list is referred. Currently, at most one rate regulator is allowed,
%% so `N' will always be `1'.</li>
%% </ol>
%%
%% * `{counter, Opts}' - counter regulator. Valid options are
%% <ol>
%%  <li>`{limit, Limit}', where `Limit' is the number of concurrent jobs
%% allowed.</li>
%%  <li>`{increment, Incr}', increment per job. Default is `1'.</li>
%%  <li>`{modifiers, Mods}', control feedback-based regulation. See below.</li>
%% </ol>
%%
%% * `{named_counter, Name, Incr}', use an existing counter, incrementing it
%% with `Incr' for each job. `Name' can either refer to a named top-level
%% counter (see {@link add_counter/2}), or a queue-specific counter
%% (these are named `{counter,Qname,N}', where `N' is an index specifying
%% their relative position in the regulators list - e.g. first or second
%% counter).
%%
%% * `{group_rate, R}', refers to a top-level group rate `R'.
%% See {@link add_group_rate/2}.
%%
%% <b>Types</b>
%%
%% * `fifo | lifo' - these are the types supported by the default queue
%% behavior. While lifo may sound like an odd choice, it may have benefits
%% for stochastic traffic with time constraints: there is no point to
%% 'fairness', since requests cannot control their place in the queue, and
%% choosing the 'freshest' job may increase overall goodness critera.
%%
%% * `{producer, F}', the queue is not for incoming requests, but rather
%% generates jobs. Valid options for `F' are
%% (for details, see {@link jobs_prod_simpe}):
%% <ol>
%%  <li>A fun of arity 0, indicating a stateless producer</li>
%%  <li>A fun of arity 2, indicating a stateful producer</li>
%%  <li>`{M, F, A}', indicating a stateless producer</li>
%%  <li>`{Mod, Args}' indicating a stateful producer</li>
%% </ol>
%%
%% * `{action, approve | reject}', specifies an automatic response to every
%% request. This can be used to either block a queue (`reject') or set it as
%% a pass-through ('approve').
%%
%% <b>Modifiers</b>
%%
%% Jobs supports feedback-based modification of regulators.
%%
%% The sampler framework sends feedback messages of type
%% `[{Modifier, Local, Remote::[{node(), Level}]}]'.
%%
%% Each regulator can specify a list of modifier instructions:
%%
%% * `{Modifier, Local, Remote}' - `Modifier' can be any label used by the
%% samplers (see {@link jobs_sampler}). `Local' and `Remote' indicate
%% increments in percent by which to reduce the limit of the given regulator.
%% The `Local' increment is used for feedback info pertaining to the local
%% node, and the `Remote' increment is used for remote indicators. `Local'
%% is given as a percentage value (e.g. `10' for `10 %'). The `Remote'
%% increment is either `{avg, Percent}' or `{max, Percent}', indicating whether
%% to respond to the average load of other nodes or to the most loaded node.
%% The correction from `Local' and the correction from `Remote' are summed
%% before applying to the regulator limit.
%%
%% * `{Modifier, Local}' - same as above, but responding only to local
%% indications, ignoring the load on remote nodes.
%%
%% * `{Modifier, F::function((Local, Remote) -> integer())}' - the function
%% `F(Local, Remote)' is applied and expected to return a correction value,
%% in percentage units.
%%
%% * `{Modifier, {Module, Function}}' - `Module:Function(Local Remote)'
%% is applied an expected to return a correction value in percentage units.
%%
%% For example, if a rate regulator has a limit of `100' and has a modifier,
%% `{cpu, 10}', then a feedback message of `{cpu, 2, _Remote}' will reduce
%% the rate limit by `2*10' percent, i.e. down to `80'.
%%
%% Note that modifiers are always applied to the <em>preset</em> limit,
%% not the current limit. Thus, the next round of feedback messages in our
%% example will be applied to the preset limit of `100', not the `80' that
%% resulted from the previous feedback messages. A correction value of `0'
%% will reset the limit to the preset value.
%%
%% If there are more than one modifier with the same name, the last one in the
%% list will be the one used.
%%
%% @end
%%
add_queue(Name, Options) ->
    jobs_server:add_queue(Name, Options).

%% @spec modify_queue(Name::any(), Options::[{Key,Value}]) ->
%%   ok | {error, Reason}
%% @doc Modifies queue parameters of existing queue.
%%
%% The queue parameters that can be modified are `max_size' and `max_time'.
%% @end
modify_queue(Name, Options) ->
    jobs_server:modify_queue(Name, Options).

%% @spec delete_queue(Name) -> boolean()
%% @doc Deletes the named queue from the load regulator on the current node.
%% Returns `true' if there was in fact such a queue; `false' otherwise.
%% @end
%%
delete_queue(Name) ->
    jobs_server:delete_queue(Name).

%% @spec ask_queue(QueueName, Request) -> Reply
%% @doc Sends a synchronous request to a specific queue.
%%
%% This function is mainly intended to be used for back-end processes that act
%% as custom extensions to the load regulator itself. It should not be used by
%% regular clients. Sophisticated queue behaviours could export gen_server-like
%% logic allowing them to respond to synchronous calls, either for special
%% inspection, or for influencing the queue state.
%% @end
%%
ask_queue(QueueName, Request) ->
    jobs_server:ask_queue(QueueName, Request).

%% @spec add_counter(Name, Options) -> ok
%% @doc Adds a named counter to the load regulator on the current node.
%% Fails if there already is a counter the name `Name'.
%% @end
%%
add_counter(Name, Options) ->
    jobs_server:add_counter(Name, Options).

%% @spec delete_counter(Name) -> boolean()
%% @doc Deletes a named counter from the load regulator on the current node.
%% Returns `true' if there was in fact such a counter; `false' otherwise.
%% @end
%%
delete_counter(Name) ->
    jobs_server:delete_counter(Name).

%% @spec add_group_rate(Name, Options) -> ok
%% @doc Adds a group rate regulator to the load regulator on the current node.
%% Fails if there is already a group rate regulator of the same name.
%% @end
%%
add_group_rate(Name, Options) ->
    jobs_server:add_group_rate(Name, Options).

delete_group_rate(Name) ->
    jobs_server:delete_group_rate(Name).

info(Item) ->
    jobs_server:info(Item).

queue_info(Name) ->
    jobs_server:queue_info(Name).

queue_info(Name, Item) ->
    jobs_server:queue_info(Name, Item).

modify_regulator(Type, QName, RegName, Opts) when Type==counter;Type==rate ->
    jobs_server:modify_regulator(Type, QName, RegName, Opts).

modify_counter(CName, Opts) ->
    jobs_server:modify_counter(CName, Opts).

modify_group_rate(GRName, Opts) ->
    jobs_server:modify_group_rate(GRName, Opts).
