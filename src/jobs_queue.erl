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
%% File    : jobs_queue.erl
%% @author  : Ulf Wiger <ulf@wiger.net>
%% @end
%% Description :
%%
%% Created : 15 Jan 2010 by Ulf Wiger <ulf@wiger.net>
%%-------------------------------------------------------------------
%% @doc Default queue behaviour for JOBS (using ordered_set ets).
%%
%% This module implements the default queue behaviour for JOBS, and also
%% specifies the behaviour itself.
%% @end

-module(jobs_queue).
-author('ulf@wiger.net').
-copyright('Ulf Wiger').

-export([new/2,
         delete/1]).
-export([in/3,
         out/2,
         peek/1,
         info/2,
         all/1,
         empty/1,
         is_empty/1,
         representation/1,
         timedout/1, timedout/2]).

-export([behaviour_info/1]).

-include("jobs.hrl").
-import(jobs_server, [timestamp/0]).

-record(st, {table}).

%-type timestamp() :: integer().
-type job()       :: {pid(), reference()}.
-type entry()     :: {timestamp(), job()}.

behaviour_info(callbacks) ->
    [{new    , 2},
     {delete , 1},
     {in     , 3},
     {peek   , 1},
     {out    , 2},
     {all    , 1},
     {info   , 2}];
behaviour_info(_) ->
    undefined.


%% @spec new(Options, #queue{}) -> #queue{}
%% @doc Instantiate a new queue.
%%
%% Options is the list of options provided when defining the queue.
%% Q is an initial #queue{} record. It can be used directly by including
%% `jobs/include/jobs.hrl', or by using exprecs-style record accessors in the
%% module `jobs_info'.
%% See <a href="http://github.com/uwiger/parse_trans">parse_trans</a> for more info
%% on exprecs. In the `new/2' function, the #queue.st attribute will normally be
%% used to keep track of the queue data structure.
%% @end
%%
new(Options, Q) ->
    case proplists:get_value(type, Options, fifo) of
	fifo ->
	    Tab = ets:new(?MODULE, [ordered_set]),
	    Q#queue{st = #st{table = Tab}}
    end.

%% @doc A representation of a queue which can be inspected
%% @end
representation(
  #queue { oldest_job = OJ,
           st = #st { table = Tab}}) ->
    Contents = ets:match_object(Tab, '$1'),
    [{oldest_job, OJ},
     {contents, [X || {X} <- Contents]}].

%% @spec delete(#queue{}) -> any()
%% @doc Queue is being deleted; remove any external data structures.
%%
%% If the queue behaviour has created an ETS table or similar, this is the place
%% to get rid of it.
%% @end
%%
delete(#queue{st = #st{table = T}}) ->
    ets:delete(T).



-spec in(timestamp(), job(), #queue{}) -> #queue{}.
%% @spec in(Timestamp, Job, #queue{}) -> #queue{}
%% @doc Enqueue a job reference; return the updated queue.
%%
%% This puts a job into the queue. The callback function is responsible for
%% updating the #queue.oldest_job attribute, if needed. The #queue.oldest_job
%% attribute shall either contain the Timestamp of the oldest job in the queue,
%% or `undefined' if the queue is empty. It may be noted that, especially in the
%% fairly trivial case of the `in/3' function, the oldest job would be
%% `erlang:min(Timestamp, PreviousOldest)', even if `PreviousOldest == undefined'.
%% @end
%%
in(TS, Job, #queue{st = #st{table = Tab}, oldest_job = OJ} = Q) ->
    OJ1 = erlang:min(TS, OJ),    % Works even if OJ==undefined
    ets:insert(Tab, {{TS, Job}}),
    Q#queue{oldest_job = OJ1}.


-spec peek(#queue{}) -> entry().
%% @spec peek(#queue{}) -> JobEntry | undefined
%% @doc Looks at the first item in the queue, without removing it.
%%
peek(#queue{st = #st{table = T}}) ->
    case ets:first(T) of
	'$end_of_table' ->
            undefined;
	Key ->
            Key
    end.

-spec out(N :: integer(), #queue{}) -> {[entry()], #queue{}}.
%% @spec out(N :: integer(), #queue{}) -> {[Entry], #queue{}}
%% @doc Dequeue a batch of N jobs; return the modified queue.
%%
%% Note that this function may need to update the #queue.oldest_job attribute,
%% especially if the queue becomes empty.
%% @end
%%
out(N,#queue{st = #st{table = T}}=Q) when N >= 0 ->
    {out1(N, T), set_oldest_job(Q)}.


-spec all(#queue{}) -> [entry()].
%% @spec all(#queue{}) -> [JobEntry]
%% @doc Return all the job entries in the queue, not removing them from the queue.
%%
all(#queue{st = #st{table = T}}) ->
    ets:select(T, [{{'$1'},[],['$1']}]).


-type info_item() :: max_time | oldest_job | length.

-spec info(info_item(), #queue{}) -> any().
%% @spec info(Item, #queue{}) -> Info
%%   Item = max_time | oldest_job | length
%% @doc Return information about the queue.
%%
info(max_time  , #queue{max_time = T}   ) -> T;
info(oldest_job, #queue{oldest_job = OJ}) -> OJ;
info(length    , #queue{st = #st{table = Tab}}) ->
    ets:info(Tab, size).

-spec timedout(#queue{}) -> {[entry()], #queue{}}.
%% @spec timedout(#queue{}) -> {[Entry], #queue{}}
%% @doc Return all entries that have been in the queue longer than MaxTime.
%%
%% NOTE: This is an inspection function; it doesn't remove the job entries.
%% @end
%%
timedout(#queue{max_time = undefined} = Q) -> {[], Q};
timedout(#queue{max_time = TO} = Q) ->
    timedout(TO, Q).

timedout(_ , #queue{oldest_job = undefined} = Q) -> {[], Q};
timedout(TO, #queue{st = #st{table = Tab}} = Q) ->
    Now = timestamp(),
    Objs = find_expired(Tab, Now, TO),
    OJ = case ets:first(Tab) of
             '$end_of_table' -> undefined;
             {TS, _} -> TS
         end,
    {Objs, Q#queue{oldest_job = OJ}}.



-spec is_empty(#queue{}) -> boolean().
%%
%% Check whether the queue is empty.
%%
is_empty(#queue{type = {producer, _}}) -> false;
is_empty(#queue{oldest_job = undefined}) -> true;
is_empty(#queue{}) ->
    false.


out1(0, _Tab) -> [];
out1(1, Tab) ->
    case ets:first(Tab) of
        '$end_of_table' ->
            [];
        {_TS,_Client} = Key ->
            ets:delete(Tab, Key),
            [Key]
    end;
out1(N, Tab) when N > 0 ->
    %% We impose an arbitrary limit of 100 jobs fetched in one chunk.
    %% The main reason for capping the limit is that ets:select/3 will
    %% crash if N is a bignum; we probably don't want to chunk that many
    %% objects anyway, so we set the limit much lower.
    Limit = erlang:min(N, 100),
    case ets:select(Tab, [{{'$1'},[],['$1']}], Limit) of
        '$end_of_table' ->
            [];
        {Keys, _} ->
            [ets:delete(Tab, K) || K <- Keys],
            Keys
    end.

set_oldest_job(#queue{st = #st{table = Tab}} = Q) ->
    OJ = case ets:first(Tab) of
             '$end_of_table' ->
                 undefined;
             {TS,_} ->
                 TS
         end,
    Q#queue{oldest_job = OJ}.


find_expired(Tab, Now, TO) ->
    find_expired(ets:first(Tab), Tab, Now, TO, []).

%% we return the reversed list, but I don't think that matters here.
find_expired('$end_of_table', _, _, _, Acc) ->
    Acc;
find_expired({TS, _} = Key, Tab, Now, TO, Acc) ->
    case is_expired(TS, Now, TO) of
	true ->
            ets:delete(Tab, Key),
            find_expired(ets:first(Tab), Tab, Now, TO, [Key|Acc]);
	false ->
            Acc
    end.

empty(#queue{st = #st{table = T}} = Q) ->
    ets:delete_all_objects(T),
    Q#queue{oldest_job = undefined}.


is_expired(TS, Now, TO) ->
    MS = Now - TS,
    MS > TO.
