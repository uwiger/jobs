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
-module(jobs_info).

-export([pp/1]).

-include("jobs.hrl").
-include_lib("parse_trans/include/exprecs.hrl").

-export_records([rr, cr, grp, rate, queue, sampler]).


pp(L) when is_list(L) ->
    [pp(X) || X <- L];
pp(X) ->
    case '#is_record-'(X) of
	true ->
	    RecName = element(1,X),
	    {RecName, lists:zip(
			'#info-'(RecName,fields),
			pp(tl(tuple_to_list(X))))};
	false ->
	    if is_tuple(X) ->
		    list_to_tuple(pp(tuple_to_list(X)));
	       true ->
		    X
	    end
    end.
