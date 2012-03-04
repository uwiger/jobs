-module(jobs_queue_model).

-compile(export_all).

-record(qm, { type = fifo,
              q    = queue:new() }).

new(_Options, Q) ->
    #qm{}.

in(Timestamp, E, #qm { q = Q} = S) ->
    S#qm { q = queue:in(E, Q)}.

out(N, #qm { q = Q} = S) ->
    {Elems, NQ} = out(N, Q, []),
    {Elems, S#qm { q = NQ}}.

out(0, Q, Taken) ->
    {lists:reverse(Taken), Q};
out(K, Q, Acc) when K > 0 ->
    case queue:out(Q) of
        {{value, E}, NQ} ->
            out(K-1, NQ, [E | Acc]);
        {empty, NQ} ->
            out(0, NQ, Acc)
    end.


