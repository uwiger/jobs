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

representation(#qm { q = Q, oj = OJ} ) ->
    Cts = queue:to_list(Q),
    [{oldest_job, OJ},
     {contents, Cts}];
representation(O) ->
    io:format("Otherwise: ~p", [O]),
    exit(fail).


