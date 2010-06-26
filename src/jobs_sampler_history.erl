-module(jobs_sampler_history).
-export([new/1,
         add/2,
         to_list/1,
         from_list/2,
         take_last/2]).

-record(jsh, {max_length,
              length = 0,
              history = queue:new()}).

new(Length) ->
    #jsh{max_length = Length}.


add(Entry, #jsh{length = L,
                max_length = L} = R) ->
    In = {timestamp(), Entry},
    do_add(In, drop(R));
add(Entry, #jsh{} = R) ->
    do_add({timestamp(), Entry}, R).


do_add(Item, #jsh{length = L, history = H} = R) ->
    R#jsh{length = L+1, history = queue:in(Item, H)}.

drop(#jsh{length = 0} = R) ->
    R;
drop(#jsh{length = L, history = H} = R) ->
    R#jsh{length = L-1, history = queue:drop(H)}.


from_list(MaxL, L0) ->
    {Length, L} = case length(L0) of
		      Len when Len > MaxL ->
			  {MaxL, lists:sublist(L0, MaxL)};
		      Len ->
			  {Len, L0}
		  end,
    #jsh{max_length = MaxL,
	 length     = Length,
	 history    = queue:from_list(L)}.

to_list(#jsh{history = Q}) ->
    queue:to_list(Q).


take_last(F, #jsh{history = Q}) ->
    take_last(F, queue:to_list(Q), []).

take_last(F, [H|T], Last) ->
    case F(H) of
        true  -> take_last(F, T, H);
        false -> Last
    end;
take_last(_, [], Last) ->
    Last.



%% Millisecond timestamp, never wraps
timestamp() ->
    job_server:timestamp() div 1000.
