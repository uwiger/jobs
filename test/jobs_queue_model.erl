-module(jobs_queue_model).

-include("jobs.hrl").

-compile(export_all).

new(_Options, Q) ->
    Q#queue { st = queue:new() }.

is_empty(#queue { st = Q}) ->
    queue:is_empty(Q).

info(oldest_job, #queue { oldest_job = OJ}) ->
    OJ;
info(max_time, #queue { max_time = MT}) -> MT;
info(length, #queue { st = Q}) ->
    queue:len(Q).

peek(#queue { st = Q }) ->
    case queue:peek(Q) of
        empty -> undefined;
        {value, K} -> K
    end.

all(#queue { st = Q}) ->
    queue:to_list(Q).

in(TS, E, #queue { st = Q,
                   oldest_job = OJ } = S) ->
    S#queue { st = queue:in({TS, E}, Q),
              oldest_job = case  OJ of undefined -> TS;
                               _ -> OJ
                           end}.

out(N, #queue { st = Q} = S) ->
    {Elems, NQ} = out(N, Q, []),
    {Elems, S#queue { st = NQ,
                      oldest_job = set_oldest_job(NQ) }}.

set_oldest_job(Q) ->
    case queue:out(Q) of
        {{value, {TS, _}}, _} ->
            TS;
        {empty, _} ->
            undefined
    end.

out(0, Q, Taken) ->
    {lists:reverse(Taken), Q};
out(K, Q, Acc) when K > 0 ->
    case queue:out(Q) of
        {{value, E}, NQ} ->
            out(K-1, NQ, [E | Acc]);
        {empty, NQ} ->
            out(0, NQ, Acc)
    end.

empty(#queue {} = Q) ->
    Q#queue { st = queue:new(),
              oldest_job = undefined }.

representation(#queue { st = Q, oldest_job = OJ} ) ->
    Cts = queue:to_list(Q),
    [{oldest_job, OJ},
     {contents, Cts}];
representation(O) ->
    io:format("Otherwise: ~p", [O]),
    exit(fail).


