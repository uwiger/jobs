-module(jobs_eqc_queue).

-include_lib("eqc/include/eqc.hrl").
-include("jobs.hrl").

-compile(export_all).

-record(model,
        { time = jobs_lib:timestamp(),
          st   = undefined }).

g_job() ->
    {make_ref(), make_ref()}.

g_scheduling_order() ->
    elements([fifo, lifo]).

g_options() ->
    [g_scheduling_order()].

g_queue_record() ->
    ?LET(N, nat(),
        #queue { max_time = N }).

g_start_time() ->
    ?LET({T, N}, {jobs_lib:timestamp(), nat()},
         T + N).

g_model() ->
    ?SIZED(Size, g_model(Size)).

g_model(0) ->
    oneof([{call, ?MODULE, new, [jobs_queue,
                                 g_options(),
                                 g_queue_record(),
                                 g_start_time()]}]);
g_model(N) ->
    frequency([{1, g_model(0)},
               {N,
                  ?LET(M, g_model(max(0, N-2)),
                       frequency(
                         [
                          {300, {call, ?MODULE, advance_time, [M, nat()]}},
                          {200, {call, ?MODULE, in, [jobs_queue, g_job(), M]}},
                          {100, {call, ?MODULE, out, [jobs_queue, nat(), M]}},
                          {1,   {call, ?MODULE, empty, [jobs_queue, M]}}
                         ]))}
              ]).

new(Mod, Opts, Q, T) ->
    #model { st = Mod:new(Opts, Q),
             time = T}.

advance_time(#model { time = T} = M, N) ->
    M#model { time = T + N}.

in(Mod, Job, #model { time = T, st = Q} = M) ->
    M#model { st = Mod:in(T, Job, Q)}.

out(Mod, N, #model { st = Q} = M) ->
    NQ = element(2, Mod:out(N, Q)),
    M#model { st = NQ }.

empty(Mod, #model { st = Q} = M) ->
    M#model { st = Mod:empty(Q)}.

is_empty(M, #model { st = Q}) ->
    M:is_empty(Q).

peek(M, #model { st = Q}) ->
    M:peek(Q).

all(M, #model { st = Q}) ->
    M:all(Q).

info(M, I, #model { st = Q}) ->
    M:info(I, Q).

g_info() ->
    oneof([oldest_job, length, max_time]).

obs() ->
    M = g_model(),
    oneof([{call, ?MODULE, all, [jobs_queue, M]},
           {call, ?MODULE, peek, [jobs_queue, M]},
           {call, ?MODULE, info, [jobs_queue, g_info(), M]},
           {call, ?MODULE, is_empty, [jobs_queue, M]}]).

model({call, ?MODULE, F, [jobs_queue | Args]}) ->
    apply(?MODULE, F, model([jobs_queue_model | Args]));
model({call, ?MODULE, F, Args}) ->
    apply(?MODULE, F, model(Args));
model([H|T]) ->
    [model(H) | model(T)];
model(X) ->
    X.

prop_oldest_job_match() ->
    ?FORALL(M, g_model(),
            begin
                R = eval(M),
                Repr = jobs_queue:representation(R#model.st),
                OJ = proplists:get_value(oldest_job, Repr),
                Cts = proplists:get_value(contents, Repr),
                case OJ of
                    undefined ->
                        Cts == [];
                    V ->
                        lists:min([TS || {TS, _} <- Cts]) == V
                end
            end).

prop_queue() ->
    ?FORALL(M, g_model(),
            equals(
              catching(fun() ->
                               R = eval(M),
                               jobs_queue:representation(R#model.st)
                       end, e),
              catching(fun () ->
                               R = model(M),
                               jobs_queue_model:representation(R#model.st)
                       end, q))).

prop_observe() ->
    ?FORALL(Obs, obs(),
            equals(
              catching(fun() -> eval(Obs) end, e),
              catching(fun() -> model(Obs) end, m))).

catching(F, T) ->
        try F()
        catch C:E ->
                io:format("Exception: ~p:~p~n", [C, E]),
                T
        end.

