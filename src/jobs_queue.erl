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
%% File    : jobs_queue.erl
%% @author  : Ulf Wiger <ulf.wiger@erlang-solutions.com>
%% @end
%% Description : 
%%
%% Created : 15 Jan 2010 by Ulf Wiger <ulf.wiger@erlang-solutions.com>
%%-------------------------------------------------------------------

-module(jobs_queue).
-author('ulf.wiger@erlang-solutions.com').
-copyright('Erlang Solutions Ltd.').

-export([new/2,
         delete/1]).
-export([in/3,
         out/2,
	 peek/1,
         info/2,
         all/1,
         empty/1,
         is_empty/1,
         timedout/1, timedout/2]).

-include("jobs.hrl").
-import(jobs_lib, [timestamp/0]).

-record(st, {table}).

%-type timestamp() :: integer().
-type job()       :: {pid(), reference()}.
-type entry()     :: {timestamp(), job()}.


new(Options, Q) ->
    case proplists:get_value(type, Options, fifo) of
        fifo ->
            Tab = ets:new(?MODULE, [ordered_set]),
            Q#q{st = #st{table = Tab}}
    end.


delete(#q{st = #st{table = T}}) ->
    ets:delete(T).


%% in(Job, Q) ->
%%     in(timestamp(), Job, Q).


-spec in(timestamp(), job(), #q{}) -> #q{}.
%%
%% Enqueue a job reference; return the updated queue
%%
in(TS, Job, #q{st = #st{table = Tab}, oldest_job = OJ} = Q) ->
    OJ1 = erlang:min(TS, OJ),    % Works even if OJ==undefined
    ets:insert(Tab, {{TS, Job}}),
    Q#q{oldest_job = OJ1}.


-spec peek(#q{}) -> entry().
peek(#q{st = #st{table = T}}) ->
    case ets:first(T) of
	'$end_of_table' ->
	    undefined;
	Key ->
	    Key
    end.

-spec out(N :: integer(), #q{}) -> {[entry()], #q{}}.
%%
%% Dequeue a batch of N jobs; return the modified queue.
%%
out(N,#q{st = #st{table = T}}=Q) when N >= 0 ->
    {out1(N, T), set_oldest_job(Q)}.


-spec all(#q{}) -> [entry()].
%%
%% Return all the job entries in the queue
%%
all(#q{st = #st{table = T}}) ->
    ets:select(T, [{{'$1'},[],['$1']}]).


-type info_item() :: max_time | oldest_job | length.

-spec info(info_item(), #q{}) -> any().
%%
%% Return information about the queue.
%%
info(max_time  , #q{max_time = T}   ) -> T;
info(oldest_job, #q{oldest_job = OJ}) -> OJ;
info(length    , #q{st = #st{table = Tab}}) ->
    ets:info(Tab, size).
    
-spec timedout(#q{}) -> [entry()].
%%
%% Return all entries that have been in the queue longer than MaxTime.
%%
timedout(#q{max_time = undefined}) -> [];
timedout(#q{max_time = TO} = Q) ->
    timedout(TO, Q).

timedout(_ , #q{oldest_job = undefined}) -> [];
timedout(TO, #q{st = #st{table = Tab}} = Q) ->
    Now = timestamp(),
    {Objs, OJ} = find_expired(Tab, Now, TO),
    {Objs, Q#q{oldest_job = OJ}}.



-spec is_empty(#q{}) -> boolean().
%%
%% Check whether the queue is empty.
%%
is_empty(#q{type = {producer, _}}) -> false;
is_empty(#q{oldest_job = undefined}) -> true;
is_empty(#q{}) ->
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

set_oldest_job(#q{st = #st{table = Tab}} = Q) ->
    OJ = case ets:first(Tab) of
             '$end_of_table' ->
                 undefined;
             {TS,_} ->
                 TS
         end,
    Q#q{oldest_job = OJ}.
            

find_expired(Tab, Now, TO) ->
    find_expired(ets:last(Tab), Tab, Now, TO, [], undefined).

%% we return the reversed list, but I don't think that matters here.
find_expired('$end_of_table', _, _, _, Acc, OJ) ->
    {Acc, OJ};
find_expired({TS, _} = Key, Tab, Now, TO, Acc, _OJ) ->
    case is_expired(TS, Now, TO) of
	true ->
	    ets:delete(Tab, Key),
	    find_expired(ets:last(Tab), Tab, Now, TO, [Key|Acc], TS);
	false ->
	    {Acc, TS}
    end.

empty(#q{st = #st{table = T}} = Q) ->
    ets:delete_all_objects(T),
    Q#q{oldest_job = undefined}.


is_expired(TS, Now, TO) ->
    MS = Now - TS,
    MS > TO.

	



