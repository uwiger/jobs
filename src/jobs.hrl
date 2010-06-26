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

-record(rate, {limit = 0,
	       preset_limit = 0,
	       interval,
	       dampers = [],
	       active_dampers = []}).

-record(rr,
        %% Rate-based regulation
        {name,
	 rate = #rate{}}).
	 % limit    = 0  :: float(),
         % interval = 0  :: undefined | float(),
	 % dampers    = []      :: [{atom(),integer()}],
	 % active_dampers = []  :: [{atom(),integer()}],
         % preset_limit = 0}).

-record(cr,
        %% Counter-based regulation
        {name,
	 rate = #rate{},
         % limit        = 5,
         % interval     = 50,
	 % dampers    = []      :: [{atom(),integer()}],
	 % active_dampers = []  :: [{atom(),integer()}],
         % preset_limit = 5,
         shared = false}).

-record(grp, {name,
	      rate = #rate{},
              latest_dispatch=0  :: integer()}).
	      % dampers    = []      :: [{atom(),integer()}],
	      % active_dampers = []  :: [{atom(),integer()}],
              % limit = 0          :: float(),
              % preset_limit = 0   :: float(),
              % interval           :: float()}).

-type regulator()      :: #rr{} | #cr{}.
-type regulator_type() :: counter | group_rate.
-type regulator_ref()  :: {regulator_type(), atom()}.

-record(q, {name                 :: atom(),
            type = fifo          :: fifo | {producer, {atom(),atom(),list()}},
            group                :: atom(),
	    table,
            regulators  = []     :: [regulator() | regulator_ref()],
            max_time             :: undefined | integer(),
            max_size             :: undefined | integer(),
            latest_dispatch = 0  :: integer(),
            check_interval       :: integer(),
            oldest_job           :: undefined | integer(),
            timer
           }).

-record(action, {name      :: atom(),
                 type      :: approve | reject}).
