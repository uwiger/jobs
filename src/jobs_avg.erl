-module(jobs_avg).

-compile(export_all).

-record(meta, {period    :: integer(),
	       slot_size :: integer(),
	       n_slots   :: integer()}).

-record(win, {meta            :: #meta{},
	      count = 0       :: integer(),
	      prev_slot = 0   :: integer(),
	      avg = <<>>      :: binary(),
	      avg_acc = {0,0} :: {integer(), integer()},
	      bin = <<>>      :: binary()}).

new(Period) ->
    new(Period, 10).

new(Period, NSlots) ->
    RealPeriod = case Period rem NSlots of
		     0 ->
			 Period;
		     _ ->
			 ((Period div NSlots) + 1) * NSlots
		 end,
    SlotSz = RealPeriod div NSlots,
    #win{meta = #meta{period = RealPeriod,
		      slot_size = SlotSz,
		      n_slots = NSlots},
	 count = 0,
	 prev_slot = jobs_server:timestamp() div SlotSz,
	 avg = << 0:NSlots/unit:16 >>}.

window(N, T, #win{meta = #meta{slot_size = SlotSz,
			       n_slots = NSlots},
		  count = C,
		  prev_slot = PrevSlot,
		  avg = Avg,
		  avg_acc = AvgAcc,
		  bin = Bin} = Win) ->
    case T div SlotSz of
	PrevSlot ->
	    Win#win{count = C + N};
	NewSlot ->
	    case NewSlot - PrevSlot of
		Diff when Diff < 0 ->
		    %% ouch! Time running backwards...
		    Win#win{count = N, prev_slot = NewSlot};
		Diff when Diff > NSlots ->
		    %% count C completely shifted out
		    B1 = << 0:NSlots/unit:16 >>,
		    {NewAvg, NewAvgAcc} = add_to_avg(C, Diff-1, Avg, AvgAcc,
						     NSlots, SlotSz),
		    Win#win{bin = B1, count = N, prev_slot = NewSlot,
			    avg = NewAvg, avg_acc = NewAvgAcc};
		Diff ->
		    Rest = (NSlots - Diff),
		    Skip = Diff - 1,
		    <<KeepBin:Rest/binary-unit:16, _/binary>> = Bin,
		    B1 = <<0:Skip/unit:16, C:16, KeepBin/binary>>,
		    {NewAvg, NewAvgAcc} = add_to_avg(C, Skip, Avg, AvgAcc,
						     NSlots, SlotSz),
		    Win#win{bin = B1, count = N, prev_slot = NewSlot,
			    avg = NewAvg, avg_acc = NewAvgAcc}
	    end
    end.

add_to_avg(C, Skip, Avg, {Sum, N}, NSlots, SlotSz) ->
    N1 = N + Skip + 1,
    if N1 < NSlots ->
	    {Avg, {Sum + C, N1}};
       true ->
	    NewSum = Sum + C,
	    A = 1000000*NewSum/(N1*SlotSz),
	    Sz = byte_size(Avg) - 8,
	    <<Bin:Sz/binary, _/float>> = Avg,
	    {<<A/float, Bin/binary>>, {0, 0}}
    end.

test_win(N, Rate, Period, Slots) when is_integer(N), N > 0,
				      is_integer(Rate), Rate > 0 ->
    test_win1(N, 0, 1000000 div Rate, new(Period, Slots)).

test_win1(N, T, Incr, #win{} = W) when N > 0 ->
    T1 = T + Incr,
    test_win1(N-1, T1, Incr, window(1, T1, W));
test_win1(0, _, _, W) ->
    W.

