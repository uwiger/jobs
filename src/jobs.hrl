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
%%% File    : jobs.hrl
%%% @author  : Ulf Wiger <ulf.wiger@erlang-solutions.com>
%%% @end
%%% Description : 
%%%
%%% Created : 15 Jan 2010 by Ulf Wiger <ulf.wiger@erlang-solutions.com>
%%%-------------------------------------------------------------------

-type job_class() :: any().
-opaque reg_obj() :: any().

-type option()     :: {queues, [q_spec()]}
                    | {group_rates, [{q_name(), [option()]}]}
		    | {counters,    [{q_name(), [option()]}]}
		    | {interval, integer()}.
-type timestamp() :: integer().  % microseconds with a special epoch

-type q_name() :: any().
-type q_std_type() :: standard_rate | standard_counter.
-type q_opts() :: [{atom(), any()}].
-type q_spec() :: {q_name(), q_std_type(), q_opts()}
		| {q_name(), q_opts()}.

-type q_modifiers() :: [q_modifier()].
-type q_modifier()  :: {cpu, integer()}     % predefined
		     | {memory, integer()}  % predefined
		     | {any(), integer()}.  % user-defined


-record(rate, {limit = 0,
	       preset_limit = 0,
	       interval,
	       modifiers = [],
	       active_modifiers = []}).

-record(rr,
        %% Rate-based regulation
        {name,
	 rate = #rate{}}).
	 % limit    = 0  :: float(),
         % interval = 0  :: undefined | float(),
	 % modifiers    = []      :: [{atom(),integer()}],
	 % active_modifiers = []  :: [{atom(),integer()}],
         % preset_limit = 0}).

-record(cr,
        %% Counter-based regulation
        {name,
         increment = 1,
	 rate = #rate{},
         % limit        = 5,
         % interval     = 50,
	 % modifiers    = []      :: [{atom(),integer()}],
	 % active_modifiers = []  :: [{atom(),integer()}],
         % preset_limit = 5,
         shared = false}).

-record(grp, {name,
	      rate = #rate{},
              latest_dispatch=0  :: integer()}).
	      % modifiers    = []      :: [{atom(),integer()}],
	      % active_modifiers = []  :: [{atom(),integer()}],
              % limit = 0          :: float(),
              % preset_limit = 0   :: float(),
              % interval           :: float()}).

-type regulator()      :: #rr{} | #cr{}.
-type regulator_type() :: counter | group_rate.
-type regulator_ref()  :: {regulator_type(), atom()}.

-record(q, {name                 :: any(),
            mod                  :: atom(),
            type = fifo          :: fifo | {producer, {atom(),atom(),list()}},
            group                :: atom(),
            regulators  = []     :: [regulator() | regulator_ref()],
            max_time             :: undefined | integer(),
            max_size             :: undefined | integer(),
            latest_dispatch = 0  :: integer(),
            check_interval       :: integer(),
            oldest_job           :: undefined | integer(),
            timer,
            st
           }).

-record(action, {name      :: atom(),
                 type      :: approve | reject}).

%% Gproc counter objects for counter-based regulation
%% Each worker process gets a counter object. The aggregated counter,
%% owned by the jobs_server, maintains a running tally of the concurrently
%% existing counter objects of the given name.
%%
-define(COUNTER(Name), {c,l,{?MODULE,Name}}).
-define(   AGGR(Name), {a,l,{?MODULE,Name}}).

-define(COUNTER_SAMPLE_INTERVAL, 20000).  % UW: how was this value picked?

%% The jobs_server may, under certain circumstances, generate error reports
%% This value, in microseconds, defines the highest frequency with which 
%% it can issue error reports. Any reports that would cause this limit to 
%% be exceeded are simply discarded.
%%
-define(MAX_ERROR_RPT_INTERVAL_US, 1000000).
