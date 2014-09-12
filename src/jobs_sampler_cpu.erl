%% -*- erlang-indent-level: 4; indent-tabs-mode: nil -*-
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
%% File    : jobs_sampler_cpu.erl
%% @author  : Ulf Wiger <ulf@wiger.net>
%% @end
%% Description :
%%
%% Created : 15 Jan 2010 by Ulf Wiger <ulf@wiger.net>
%%-------------------------------------------------------------------
-module(jobs_sampler_cpu).
-behaviour(jobs_sampler).

-export([init/2,
         sample/2,
	 handle_msg/3,
         calc/2]).

-record(st, {levels = []}).

default_levels() -> [{80,1},{90,2},{100,3}].


init(_Name, Opts) ->
    cpu_sup:util([per_cpu]),  % first return value is rubbish, per the docs
    Levels = proplists:get_value(levels, Opts, default_levels()),
    {ok, #st{levels = Levels}}.

handle_msg(_Msg, _Timestamp, ModS) ->
    {ignore, ModS}.

sample(_Timestamp, #st{} = S) ->
    Result =
        case cpu_sup:util([per_cpu]) of
            Info when is_list(Info) ->
                Utils = [U || {_,U,_,_} <- Info],
                case Utils of
                    [U] ->
                        %% only one cpu
                        U;
                    [_,_|_] ->
                        %% This is a form of ad-hoc averaging, which tries to
                        %% account for the possibility that the application
                        %% loads the cores unevenly.
                        calc_avg_util(Utils)
                end;
            _ ->
                undefined
        end,
    {Result, S}.

calc_avg_util(Utils) ->
    case minmax(Utils) of
        {A,B} when B-A > 50 ->
            %% very uneven load
            High = [U || U <- Utils,
                         B-U > 20],
            lists:sum(High)/length(High);
        {Low,High} ->
            (High+Low)/2
    end.


minmax([H|T]) ->
    lists:foldl(
      fun(X, {Min,Max}) ->
              {erlang:min(X,Min), erlang:max(X,Max)}
      end, {H,H}, T).


calc(History, #st{levels = Levels} = St) ->
    L = jobs_sampler:calc(value, Levels, History),
    {[{cpu,L}], St}.
