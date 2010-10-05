-module(jobs_server_tests).


-include_lib("eunit/include/eunit.hrl").


rate_test_() ->
     {foreachx,
      fun(Type) -> start_test_server(Type) end,
      fun(_, _) -> stop_server() end,
      [{{rate,1}, fun(O,_) -> [fun() -> serial(1,2,2) end] end}
       , {{rate,   5}, fun(O,_) -> [fun() -> serial(5,5,1) end] end}
       %% , {{rate, 100}, fun(O,_) -> [fun() -> rate_test(O,1) end] end}
       , {{rate, 400}, fun(O,_) -> [fun() -> par_run(400,400,1) end] end}
       , {{rate, 600}, fun(O,_) -> [fun() -> par_run(600,600,1) end] end}
       , {{rate,1000}, fun(O,_) -> [fun() -> par_run(1000,1000,1) end] end}
       %% , {[{rate,100},
       %% 	   {group,50}], fun(O,_) -> [fun() -> max_rate_test(O,1) end] end}
       , {{count,3}, fun(O,_) -> [fun() -> counter_run(30,1) end] end}
      ]}.



serial(R, N, TargetRatio) ->
    Expected = (N div R) * 1000000 * TargetRatio,
    ?debugVal({R,N,Expected}),
    {T,Ts} = tc(fun() -> run_jobs(q,N) end),
    time_eval(R, N, T, Ts, Expected).

par_run(R, N, TargetRatio) ->
    Expected = (N div R) * 1000000 * TargetRatio,
    ?debugVal({R,N,Expected}),
    {T,Ts} = tc(fun() -> pmap(fun() ->
				      run_job(q, one_job(time))
			      end, N)
		end),
    time_eval(R, N, T, Ts, Expected).

counter_run(N, Target) ->
    ?debugVal({N, Target}),
    {T, Ts} = tc(fun() ->
			 pmap(fun() -> run_job(q, one_job(count)) end, N)
		 end),
    ?debugVal({T,Ts}).

time_eval(R, N, T, Ts, Expected) ->
    [{Hd,_}|Tl] = lists:sort(Ts),
    Diffs = [X-Hd || {X,_} <- Tl],
    Ratio = T/Expected,
    Max = lists:max(Diffs),
    {Mean, Variance} = time_variance(Diffs),
    io:fwrite(user,
	      "Time: ~p, Ratio = ~.1f, Max = ~p, "
	      "Mean = ~.1f, Variance = ~.1f~n",
	      [T, Ratio, Max, Mean, Variance]).
    

time_variance(L) ->
    N = length(L),
    Mean = lists:sum(L) / N,
    SQ = fun(X) -> X*X end,
    {Mean, math:sqrt(lists:sum([SQ(X-Mean) || X <- L]) / N)}.
		 


counter_test(Count) ->
    start_test_server({count,Count}),
    Res = tc(fun() ->
		     pmap(fun() -> jobs:run(q, one_job(count)) end, Count * 2)
	     end),
    io:fwrite(user, "~p~n", [Res]),
    stop_server().


pmap(F, N) ->
    Pids = [spawn_monitor(fun() -> exit(F()) end) || _ <- lists:seq(1,N)],
    collect(Pids).

collect([{_P,Ref}|Ps]) ->
    receive
	{'DOWN', Ref, _, _, Res} ->
	    [Res|collect(Ps)]
    end;
collect([]) ->
    [].
			       

start_test_server({rate,Rate}) ->
    start_with_conf([{queues, [{q, [{regulators,
				     [{rate,[
					     {limit, Rate}]
				      }]}
				    %% , {mod, jobs_queue_list}
				   ]}
			      ]}
		    ]),
    Rate;
start_test_server([{rate,Rate},{group,Grp}]) ->
    start_with_conf([{group_rates, [{gr, [{limit, Grp}]}]},
		     {queues, [{q, [{regulators,
				     [{rate,[{limit, Rate}]},
				      {group_rate, gr}]}
				   ]}
			      ]}
		    ]),
    Grp;
start_test_server({count, Count}) ->
    start_with_conf([{queues, [{q, [{regulators,
				     [{counter,[
						{limit, Count}
					       ]
				      }]}
				   ]}
			      ]}
		    ]).

start_with_conf(Conf) ->
    application:unload(jobs),
    application:load(jobs),
    [application:set_env(jobs, K, V) ||	{K,V} <- Conf],
    error_logger:delete_report_handler(error_logger_tty_h),
    application:start(gproc),
    application:start(jobs).


stop_server() ->
    application:stop(jobs),
    application:stop(gproc).

tc(F) ->
    T1 = erlang:now(),
    R = (catch F()),
    T2 = erlang:now(),
    {timer:now_diff(T2,T1), R}.

run_jobs(Q,N) ->
    [run_job(Q, one_job(time)) || _ <- lists:seq(1,N)].

run_job(Q,F) ->
    timer:tc(jobs,run,[Q,F]).

one_job(time) ->
    fun timestamp/0;
one_job(count) ->
    fun() ->
	    gproc:lookup_local_aggr_counter({jobs_server,{counter,q,1}})
    end.


timestamp() ->
    jobs_server:timestamp().
