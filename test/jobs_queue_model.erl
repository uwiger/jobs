-module(jobs_queue_model).

-include("jobs.hrl").

-compile(export_all).

new(Options, Q) ->
    case proplists:get_value(type, Options) of
        fifo ->
            Q#queue { type = fifo,
                      st = queue:new() };
        lifo ->
            Q#queue { type = lifo,
                      st = queue:new() }
    end.

is_empty(#queue { st = Q}) ->
    queue:is_empty(Q).

info(oldest_job, #queue { oldest_job = OJ}) ->
    OJ;
info(max_time, #queue { max_time = MT}) -> MT;
info(length, #queue { st = Q}) ->
    queue:len(Q).

peek(#queue { type = fifo, st = Q }) ->
    case queue:peek(Q) of
        empty -> undefined;
        {value, K} -> K
    end;
peek(#queue { type = lifo, st = Q }) ->
    case queue:peek_r(Q) of
        empty -> undefined;
        {value, K} -> K
    end.

all(#queue { type = fifo, st = Q}) ->
    queue:to_list(Q);
all(#queue { type = lifo, st = Q}) ->
    queue:to_list(queue:reverse(Q)).

in(TS, E, #queue { st = Q,
                   oldest_job = OJ } = S) ->
    S#queue { st = queue:in({TS, E}, Q),
              oldest_job = case  OJ of undefined -> TS;
                               _ -> OJ
                           end}.

out(N, #queue { type = Ty, st = Q} = S) ->
    {Elems, NQ} = out(Ty, N, Q, []),
    {Elems, S#queue { st = NQ,
                      oldest_job = set_oldest_job(Ty, NQ) }}.

set_oldest_job(fifo, Q) ->
    case queue:out(Q) of
        {{value, {TS, _}}, _} ->
            TS;
        {empty, _} ->
            undefined
    end;
set_oldest_job(lifo, Q) ->
    case queue:out(Q) of
        {{value, {TS, _}}, _} ->
            TS;
        {empty, _} ->
            undefined
    end.

out(fifo, 0, Q, Taken) ->
    {lists:reverse(Taken), Q};
out(lifo, 0, Q, Taken) ->
    {Taken, Q};
out(fifo, K, Q, Acc) when K > 0 ->
    case queue:out(Q) of
        {{value, E}, NQ} ->
            out(fifo, K-1, NQ, [E | Acc]);
        {empty, NQ} ->
            out(fifo, 0, NQ, Acc)
    end;
out(lifo, K, Q, Acc) ->
    case queue:out_r(Q) of
        {{value, E}, NQ} ->
            out(lifo, K-1, NQ, [E | Acc]);
        {empty, NQ} ->
            out(lifo, 0, NQ, Acc)
    end.


empty(#queue {} = Q) ->
    Q#queue { st = queue:new(),
              oldest_job = undefined }.

representation(#queue { type = fifo, st = Q, oldest_job = OJ} ) ->
    Cts = queue:to_list(Q),
    [{oldest_job, OJ},
     {contents, Cts}];
representation(#queue { type = lifo, st = Q, oldest_job = OJ} ) ->
    Cts = queue:to_list(queue:reverse(Q)),
    [{oldest_job, OJ},
     {contents, Cts}];
representation(O) ->
    io:format("Otherwise: ~p", [O]),
    exit(fail).


