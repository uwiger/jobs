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

-module(performance_logger).
-behaviour(gen_server).

%% Interface
-export([start_link/0,
         increment_counter/2,
         decrement_counter/2,
         set_counter/2,
         start_recording/1,
         end_recording/0,
         save_recorded_data_to_file/1]).

%% gen_server-specific
-export([init/1,
         handle_cast/2]).

%% internal
-export([tick/0]).

%% testing
-export([test_recording/0]).

-export([spec_to_gnuplot_script/1]).

-define(SAMPLING_TIME, 125). %% Duration between samples, in msec.
-define(PFL_ETS_NAME, pfl_stats).

-define(TIME_COMPUTATION_SCALE, 1).

%% :)
-define(WITH_OPEN_FILE(Anaphora,FileName,Modes,Code), case file:open(FileName,Modes) of
                                                          {ok, Anaphora} -> Code, file:close(Anaphora);
                                                          SthElse -> SthElse
                                                      end).

%% Data spec description
-type counter_type() :: fun(() -> any()) | atom(). %% For custom counters one can supply a 0-arity fun instead of an usual name.
-type counter_name() :: string(). %% Name used on chart as a label.
-type sampling_type() :: diff | identity | accumulate.
-type data_spec() :: [{counter_type(), counter_name(), sampling_type()}].


%% GENSERVERIFY BEGIN
%% Interface
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%% Counter operations
increment_counter(CounterName, Increment) ->
    gen_server:cast(?MODULE, {incf, CounterName, Increment}).

decrement_counter(CounterName, Decrement) ->
    gen_server:cast(?MODULE, {decf, CounterName, Decrement}).

set_counter(CounterName, NewValue) ->
    gen_server:cast(?MODULE, {setf, CounterName, NewValue}).

%%% Data recording
%% Note the DataSpec.
-spec start_recording(DataSpec :: data_spec()) -> any().
start_recording(DataSpec) ->
    gen_server:cast(?MODULE, {start_recording, DataSpec}).

end_recording() ->
    gen_server:cast(?MODULE, end_recording).

save_recorded_data_to_file(FileName) ->
    gen_server:cast(?MODULE, {save_data, FileName}).

%% A call to tick causes the Logger to take a snapshot of current counter values and save that as a sample.
%% NOTE if we get flooded with calls to
%% increment/decrement/set_counter and gen_server starts falling
%% behind, delays between samples may not exactly match the specified rate.
tick() ->
    gen_server:cast(?MODULE, ping).

%% Implementation
-record(state, {data_spec, %% data spec, see description at the top of the file
                start_time, %% the time of the start of start_recording,it is used to calculate the offset from this start time, the offset is used to indicate the descending order of the ets table "pfl_stats" key
                timer}). %% reference to timer that makes us take samples every now and then

init(_State) ->
    ets:new(?PFL_ETS_NAME, [ordered_set, named_table, public]),
    {ok, #state{}}.

handle_cast({incf, CounterName, Increment}, _State) ->
    setf(CounterName, getf(CounterName) + Increment),
    {noreply, _State};

handle_cast({decf, CounterName, Decrement}, _State) ->
    setf(CounterName, getf(CounterName) - Decrement),
    {noreply, _State};

handle_cast({setf, CounterName, NewValue}, _State) ->
    setf(CounterName, NewValue),
    {noreply, _State};

%%% Data collection
handle_cast(ping, State = #state{data_spec = DataSpec}) ->
    NewSample = calculate_sample(DataSpec),
    store_sample({compute_time_offset(State), NewSample}),
    {noreply, State};

%%% Data recording
%% Note the DataSpec.
handle_cast({start_recording, DataSpec}, State) ->
    ets:delete_all_objects(?PFL_ETS_NAME),
    {ok, TRef} = timer:apply_interval(?SAMPLING_TIME, ?MODULE, tick, []),
    {noreply, State#state{start_time = os:timestamp(),
                          %% we add two default counters, that measure CPU load and memory usage.
                          data_spec = [{fun cpu_load/0, "CPULoad", identity},
                                       {fun memory_use/0, "MemoryUse", identity} | DataSpec],
                          timer = TRef}};

handle_cast(end_recording, State) ->
    timer:cancel(State#state.timer),
    {noreply, State};


handle_cast({save_data, FileName}, State = #state{data_spec = DataSpec}) ->
    FirstElement = first_element(),
    ?WITH_OPEN_FILE(File, FileName, [write],
                    begin
                        save_header(DataSpec, File),
                        save_data(FirstElement,
                                  next_element(FirstElement),
                                  lists:duplicate(length(DataSpec), 0), %% we need an auxiliary list for each counter, initialized to all zeros
                                  DataSpec,
                                  File)
                    end),
    {noreply, State}.

sample_to_string({Timestamp, Entry}) ->
    io_lib:format("~p~s~n", [Timestamp, lists:foldl(fun(W, Acc) -> Acc ++  "\t" ++ io_lib:format("~p",[W]) end, [], Entry)]).

%% Measure an approximate current CPU load value.
cpu_load() ->
    cpu_sup:util().
memory_use() ->
    erlang:memory(total).

store_sample(Sample) ->
    ets:insert(?PFL_ETS_NAME, Sample).

%%%% Tools for victory. No refunds.
%%%% (also, not really tested)
setf(Counter, Value) ->
    put(Counter, Value).

getf(Counter) when is_function(Counter) ->
    Counter();

%% NOTE that getf will convert 'undefined' atom to 0, so that
%% we may assume we're working with numerical counters.
getf(Counter) ->
    case get(Counter) of
        undefined ->
            0;
        Value ->
            Value
    end.


calculate_sample(Counters) ->
    lists:map(fun({Counter, _Name, _SamplingType}) ->
                      getf(Counter) end,
              Counters).

compute_time_offset(#state{start_time = StartTime}) ->
    timer:now_diff(os:timestamp(), StartTime) * ?TIME_COMPUTATION_SCALE.

%%
save_header(DataSpec, File) ->
    file:write(File, "Timestamp" ++ lists:foldl(fun({_, Name, _}, Acc) -> Acc ++  "\t" ++ Name end, [], DataSpec) ++ "\n").

%% Save measured data to file.
%% save_data(Stream of data,
%%           Stream of data, shifted by one element left,
%%           Additional buffer for integration,
%%           DataSpec,
%%           File to save to).
%%
%% All data in the input stream represent the measured values of counters. However, the API allows us to specify that
%% some counters should have their data integrated, and others should record differences between recent values.
%% Feeding in the data stream both as normal and shifted by one element allows us to compute differences, while
%% additional buffer allows us to integrate specific counters.
save_data(_, end_of_data, _, _, _) ->
    ok;
save_data(Fn_1, Fn = {Timestamp, _}, Result, Data, File) ->
    Out = compute_sample_value(Fn_1, Fn, Result, Data),
    file:write(File, sample_to_string({Timestamp, Out})),
    save_data(Fn, next_element(Fn), Out, Data, File).

compute_sample_value({_, Fn_1}, {_, Fn}, Result, Data) ->
    zipwith4(fun(Cntr_prev, Cntr, Cntr_local, {_, _, CntrType}) ->
                     case CntrType of
                         identity -> Cntr;
                         diff -> Cntr - Cntr_prev;
                         accumulate -> Cntr + Cntr_local
                     end
             end,
             Fn_1,
             Fn,
             Result,
             Data).

%% Helper functions for working with stream that comes from a specific ETS table.
first_element() ->
    [WhatINeed] = ets:lookup(?PFL_ETS_NAME, ets:first(?PFL_ETS_NAME)),
    WhatINeed.

next_element({Key, _Value}) ->
    case ets:next(?PFL_ETS_NAME, Key) of
        '$end_of_table' -> end_of_data;
        NextKey -> [WhatINeed] = ets:lookup(?PFL_ETS_NAME, NextKey),
                   WhatINeed
    end.

%% zipwith4 - lists:zipwith for 4 lists.
zipwith4(Combine, List1, List2, List3, List4) ->
    zipwith4(Combine, List1, List2, List3, List4, []).

zipwith4(_, [], [], [], [], Accu) ->
    lists:reverse(Accu);
zipwith4(Combine, [H1 | T1], [H2 | T2], [H3 | T3], [H4 | T4], Accu) ->
    zipwith4(Combine, T1, T2, T3, T4, [Combine(H1, H2, H3, H4) | Accu]).

%% TODO needs real implementation
spec_to_gnuplot_script(DataSpec) ->
    io_lib:format("set terminal png transparent nocrop enhanced font arial 8 size 800,600

set autoscale y
set autoscale y2

set key autotitle columnhead

plot \"foobar\" ", []).


%% Test if the whole recording business works.
%% NOTE, to verify the test, one needs to inspect the proper .txt file saved by it.
test_recording() ->
    increment_counter(foobar, 42),
    increment_counter(firebirds, 15),
    increment_counter(jane, 24),
    start_recording([{foobar, "foobziubar", identity},
                     {jane, "JaneDwim", diff},
                     {firebirds, "24zachody", accumulate}]),
    timer:sleep(500),
    decrement_counter(foobar, 42),
    decrement_counter(jane, 14),
    decrement_counter(firebirds, 14),
    timer:sleep(1500),
    decrement_counter(foobar, 42),
    decrement_counter(jane, 14),
    decrement_counter(firebirds, 14),
    timer:sleep(1500),
    decrement_counter(foobar, 42),
    decrement_counter(firebirds, 14),
    timer:sleep(1500),
    increment_counter(foobar, 45),
    increment_counter(jane, 55),
    increment_counter(firebirds, 55),
    timer:sleep(1500),
    increment_counter(jane, 55),
    timer:sleep(1500),
    end_recording(),
    save_recorded_data_to_file("itworks.txt").
