%%% The contents of this file are subject to the Erlang Public License,
%%% Version 1.0, (the "License"); you may not use this file except in
%%% compliance with the License. You may obtain a copy of the License at
%%% http://www.erlang.org/license/EPL1_0.txt
%%%
%%% Software distributed under the License is distributed on an "AS IS"
%%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%%% the License for the specific language governing rights and limitations
%%% under the License.
%%%
%%% The Original Code is jobs-0.1.
%%%
%%% The Initial Developer of the Original Code is Ericsson AB.
%%% Portions created by Ericsson are Copyright (C), 2006, Ericsson AB.
%%% All Rights Reserved.
%%%
%%% Contributor(s): ______________________________________.

%%%-------------------------------------------------------------------
%%% File    : jobs_queue.erl
%%% @author  : Ulf Wiger <ulf.wiger@erlang-solutions.com>
%%% @end
%%% Description : 
%%%
%%% Created : 15 Jan 2010 by Ulf Wiger <ulf.wiger@erlang-solutions.com>
%%%-------------------------------------------------------------------

-module(jobs_queue_list).
-author('ulf.wiger@erlang-solutions.com').
-copyright('Erlang Solutions Ltd.').

-export([new/2,
         delete/1]).
-export([in/3,
         out/2,
         info/2,
         all/1,
         empty/1,
         is_empty/1,
         timedout/1, timedout/2]).

-include("jobs.hrl").
-import(jobs_lib, [timestamp/0]).

%-type timestamp() :: integer().
-type job()       :: {pid(), reference()}.
-type entry()     :: {timestamp(), job()}.


new(Options, Q) ->
    case proplists:get_value(type, Options, lifo) of
	lifo -> Q#q{st = []}
    end.

delete(#q{}) -> true.

-spec in(timestamp(), job(), #q{}) -> #q{}.
%%
%% Enqueue a job reference; return the updated queue
%%
in(TS, Job, #q{st = []} = Q) ->
    Q#q{st = [{TS, Job}], oldest_job = TS};
in(TS, Job, #q{st = L} = Q) ->
    Q#q{st = [{TS, Job} | L]}.

-spec out(N :: integer(), #q{}) -> {[entry()], #q{}}.
%%
%% Dequeue a batch of N jobs; return the modified queue.
%%
out(N, #q{st = L, oldest_job = OJ} = Q) when N >= 0 ->
    {Out, Rest} = split(N, L),
    OJ1 = case Rest of
	      [] -> undefined;
	      _  -> OJ
	  end,
    {Out, Q#q{st = Rest, oldest_job = OJ1}}.

split(N, L) ->
    split(N, L, []).

split(_, [], Acc) ->
    {lists:reverse(Acc), []};
split(N, [H|T], Acc) when N > 0 ->
    split(N-1, T, [H|Acc]);
split(0, T, Acc) ->
    {lists:reverse(Acc), T}.




-spec all(#q{}) -> [entry()].
%%
%% Return all the job entries in the queue
%%
all(#q{st = L}) ->
    L.


-type info_item() :: max_time | oldest_job | length.

-spec info(info_item(), #q{}) -> any().
%%
%% Return information about the queue.
%%
info(max_time  , #q{max_time = T}   ) -> T;
info(oldest_job, #q{oldest_job = OJ}) -> OJ;
info(length    , #q{st = L}) ->
    length(L).
    
-spec timedout(#q{}) -> [entry()].
%%
%% Return all entries that have been in the queue longer than MaxTime.
%%
timedout(#q{max_time = undefined}) -> [];
timedout(#q{max_time = TO} = Q) ->
    timedout(TO, Q).

timedout(_ , #q{oldest_job = undefined}) -> [];
timedout(TO, #q{st = L} = Q) ->
    Now = timestamp(),
    {Left, Timedout} = lists:splitwith(fun({TS,_}) ->
					       not(is_expired(TS,Now,TO)) 
				       end, L),
    OJ = get_oldest_job(Left),
    {Timedout, Q#q{oldest_job = OJ, st = Left}}.

get_oldest_job([]) -> undefined;
get_oldest_job(L) ->
    element(1, hd(lists:reverse(L))).


-spec is_empty(#q{}) -> boolean().
%%
%% Check whether the queue is empty.
%%
is_empty(#q{st = []}) -> true;
is_empty(_) ->
    false.

empty(#q{} = Q) ->
    Q#q{oldest_job = undefined, st = []}.

is_expired(TS, Now, TO) ->
    MS = Now - TS,
    MS > TO.

	



