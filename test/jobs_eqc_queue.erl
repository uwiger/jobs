-module(jobs_eqc_queue).

-include_lib("eqc/include/eqc.hrl").
-include("jobs.hrl").

-compile(export_all).

g_job() ->
    {make_ref(), make_ref()}.

g_scheduling_order() ->
    elements([fifo, lifo]).

g_options() ->
    [g_scheduling_order()].

g_queue_record() ->
    ?LET(N, nat(),
        #queue { max_time = N }).

g_queue() ->
    ?SIZED(Size, g_queue(Size)).

g_queue(0) ->
    oneof([{call, jobs_queue, new, [g_options(),
                                    g_queue_record()]}]);
g_queue(N) ->
    frequency([{1, g_queue(0)},
               {N,
                  ?LET(Q, g_queue(max(0, N-2)),
                       frequency(
                         [{2, oneof(
                                [{call, jobs_queue, in, [0,
                                                         g_job(), Q]}])},
                          {1, oneof(
                               [{call, ?MODULE, out, [nat(), Q]}])}]))}]).

out(N, Q) ->
    element(2, jobs_queue:out(N, Q)).

g_info() ->
    oneof([oldest_job, length, max_time]).

obs() ->
    Q = g_queue(),
    oneof([{call, jobs_queue, all, [Q]},
           {call, jobs_queue, peek, [Q]},
           {call, jobs_queue, info, [g_info(), Q]},
           {call, jobs_queue, is_empty, [Q]}]).

model({call, _, F, Args}) ->
    apply(jobs_queue_model, F, model(Args));
model([H|T]) ->
    [model(H) | model(T)];
model(X) ->
    X.

prop_queue() ->
    ?FORALL(Q, g_queue(),
            equals(
              catching(fun() -> jobs_queue:representation(
                                  eval(Q))
                       end, e),
              catching(fun () -> jobs_queue_model:representation(
                                   model(Q))
                       end, q))).

prop_observe() ->
    ?FORALL(Obs, obs(),
            equals(
              catching(fun() -> eval(Obs) end, e),
              catching(fun() -> model(Obs) end, m))).

catching(F, T) ->
        try F()
        catch C:E ->
                io:format("Exception: ~p:~p", [C, E]),
                T
        end.

