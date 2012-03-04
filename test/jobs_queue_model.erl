-module(jobs_queue_model).

-compile(export_all).

-record(qm, { type = fifo,
              oj   = undefined,
              q    = queue:new() }).

new(_Options, Q) ->
    #qm{}.

in(TS, E, #qm { q = Q} = S) ->
    S#qm { q = queue:in({TS, E}, Q),
           oj = TS }.

out(N, #qm { q = Q} = S) ->
    {Elems, NQ} = out(N, Q, []),
    S#qm { q = NQ,
           oj = set_oldest_job(NQ) }.

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

representation(#qm { q = Q, oj = OJ} ) ->
    Cts = queue:to_list(Q),
    [{oldest_job, OJ},
     {contents, Cts}];
representation(O) ->
    io:format("Otherwise: ~p", [O]),
    exit(fail).


