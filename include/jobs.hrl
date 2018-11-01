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
%% File    : jobs.hrl
%% @author  : Ulf Wiger <ulf@wiger.net>
%% @end
%% Description :
%%
%% Created : 15 Jan 2010 by Ulf Wiger <ulf@wiger.net>
%%-------------------------------------------------------------------

-export_type([counter/0, reg_obj/0]).

-type job_class() :: any().

-type mod_args() :: {atom(), list()}.
-type mod_fun() :: {atom(), atom()}.

-type option() :: {queues, [q_spec()]}
                | {config, file:name()}
                | {group_rates, [{q_name(), [option()]}]}
                | {counters,    [{q_name(), [option()]}]}
                | {interval, integer()}.
-type timestamp() :: integer().  % microseconds with a special epoch


-type q_name() :: any().
-type q_std_type() :: standard_rate | standard_counter.
-type q_check_interval() :: integer() | infinity | mfa().
-type q_producer() :: fun() | mfa() | mod_args().

-type q_reg_rate() :: {limit, integer()}
                    | {modifiers, q_modifiers()}
                    | {name, any()}.
-type q_reg_counter() :: {limit, integer()}
                       | {increment, integer()}
                       | {modifiers, q_modifiers()}
                       | {name, any()}.
-type q_reg_opt() :: {rate, q_reg_rate()}
                   | {counter, q_reg_counter()}
                   | {named_counter, any(), integer()}
                   | {group_rate, q_reg_rate()}.
-type q_opt_action() :: approve | reject.
-type q_opt_type() :: fifo | lifo | {producer, q_producer()}
                    | {action, q_opt_action()}.

-type q_opt() :: {regulators, [q_reg_opt()]}
               | {type, q_opt_type()}
               | {producer, q_producer()}
               | passive
               | {passive, fifo}
               | {action, q_opt_action()}
               | q_opt_action()
               | {check_interval, q_check_interval()}
               | {max_time, integer()}
               | {max_size, integer()}
               | {mod, atom()}
               | {standard_rate, integer()}
               | {standard_counter, integer()}.
            

-type q_opts() :: [q_opt()].
-type q_spec() :: {q_name(), q_std_type(), q_opts()}
                | {q_name(), q_opts()}.

-type q_modifier_name() :: cpu    % predefined
                         | memory % predefined
                         | any(). % user-defined

-type q_modifier_remote() :: {avg | max, integer()}.
-type q_modifier()  :: {q_modifier_name(), integer()}
                     | {q_modifier_name(), integer(), q_modifier_remote()}
                     | {q_modifier_name(), fun(
                        (integer(), q_modifier_remote()) -> integer()
                        )}
                     | {q_modifier_name(), mod_fun()}.
-type q_modifiers() :: [q_modifier()].


-record(rate, {limit = 0,
           preset_limit = 0,
           interval,
           modifiers = [],
           active_modifiers = []}).

-record(counter, {name, increment = undefined}).
-record(group_rate, {name}).

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
     value = 0,
     rate = #rate{},
     owner,
     queues = [],
         % limit        = 5,
         % interval     = 50,
     % modifiers    = []      :: [{atom(),integer()}],
     % active_modifiers = []  :: [{atom(),integer()}],
         % preset_limit = 5,
         shared = false}).

-opaque counter() :: {#cr{}, non_neg_integer()}.
-opaque reg_obj() :: {reference(), [{info, any()} | {counters, [counter()]}]}.

-record(grp, {name,
          rate = #rate{},
              latest_dispatch=0  :: integer()}).
          % modifiers    = []      :: [{atom(),integer()}],
          % active_modifiers = []  :: [{atom(),integer()}],
              % limit = 0          :: float(),
              % preset_limit = 0   :: float(),
              % interval           :: float()}).

-type regulator()      :: #rr{} | #cr{} | regulator_ref().
-type regulator_ref()  :: #group_rate{} | #counter{}.


%% -record(producer, {f={erlang,error,[undefined_producer]}
%%                 :: mfa() | fun(),
%%                 mode = spawn :: spawn | {stateful, }).
-record(producer, {mod = jobs_prod_simple,
                   state}).

%% -record(producer, {f={erlang,error,[undefined_producer]}
%%         :: mfa() | fun()}).
-record(passive , {type = fifo   :: fifo}).
-record(action  , {a = approve   :: q_opt_action()}).

-record(queue, {name                 :: any(),
        mod                  :: atom(),
        type = fifo          :: fifo | lifo | #producer{} | #passive{}
                              | #action{} | q_opt_type(),
        group                :: atom(),
        regulators  = []     :: [regulator() | regulator_ref()],
        max_time             :: integer() | undefined,
        max_size             :: integer() | undefined,
        latest_dispatch = 0  :: integer(),
        approved = 0,
        queued = 0,
        check_interval       :: q_check_interval() | undefined,
        oldest_job           :: integer() | undefined,
        timer,
        check_counter = 0    :: integer(),
        empty = false        :: boolean(),
        depleted = false     :: boolean(),
        waiters = []         :: [{pid(), reference()}],
        stateful,
        st
           }).

-record(sampler, {name,
                  mod,
                  mod_state,
                  type,    % binary | meter
                  step,    % {seconds, [{Secs,Step}]}|{levels,[{Level,Step}]}
          hist_length = 10,
                  history = queue:new()}).

-record(stateless, {f}).
-record(stateful, {f, st}).

%% Gproc counter objects for counter-based regulation
%% Each worker process gets a counter object. The aggregated counter,
%% owned by the jobs_server, maintains a running tally of the concurrently
%% existing counter objects of the given name.
%%
-define(COUNTER(Name), {c,l,{?MODULE,Name}}).
-define(   AGGR(Name), {a,l,{?MODULE,Name}}).

-define(COUNTER_SAMPLE_INTERVAL, infinity).

%% The jobs_server may, under certain circumstances, generate error reports
%% This value, in microseconds, defines the highest frequency with which
%% it can issue error reports. Any reports that would cause this limit to
%% be exceeded are simply discarded.
%
-define(MAX_ERROR_RPT_INTERVAL_US, 1000000).
