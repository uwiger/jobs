%%==============================================================================
%% Copyright 2010 Erlang Solutions Ltd.
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
%% @author  : Ulf Wiger <ulf.wiger@erlang-solutions.com>
%% @end
%% Description : 
%%
%% Created : 15 Jan 2010 by Ulf Wiger <ulf.wiger@erlang-solutions.com>
%%-------------------------------------------------------------------
-module(jobs).

-export([ask/1,
	 done/1,
	 run/2]).

%% Configuration API
-export([add_queue/2,
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
run(Queue, F) when is_function(F, 0) ->
    jobs_server:run(Queue, F).


add_queue(Name, Options) ->
    jobs_server:add_queue(Name, Options).

delete_queue(Name) ->
    jobs_server:delete_queue(Name).

add_counter(Name, Options) ->
    jobs_server:add_counter(Name, Options).

delete_counter(Name) ->
    jobs_server:delete_counter(Name).

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
