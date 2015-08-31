-module(jobs_server_tests).


-include_lib("eunit/include/eunit.hrl").

rate_test_() ->
     {foreachx,
      fun(Type) -> start_test_server(Type) end,
      fun(_, _) -> stop_server() end,
      [{{rate,1}, fun(_,_) -> [fun() -> serial(1,2,2) end] end}
       , {{rate,   5}, fun(_,_) -> [fun() -> serial(5,5,1) end] end}
       , {{rate,   50}, fun(_,_) -> [fun() -> serial(50,50,1) end] end}
       , {{rate,   100}, fun(_,_) -> [fun() -> serial(100,100,1) end] end}
       , {{rate,   300}, fun(_,_) -> [fun() -> serial(300,300,1) end] end}
       , {{rate,   500}, fun(_,_) -> [fun() -> serial(500,500,1) end] end}
       , {{rate,   1000}, fun(_,_) -> [fun() -> serial(1000,1000,1) end] end}
       %% , {{rate, 100}, fun(O,_) -> [fun() -> rate_test(O,1) end] end}
       , {{rate, 400}, fun(_,_) -> [fun() -> par_run(400,400,1) end] end}
       , {{rate, 600}, fun(_,_) -> [fun() -> par_run(600,600,1) end] end}
       , {{rate,1000}, fun(_,_) -> [fun() -> par_run(1000,1000,1) end] end}
       , {{rate,2000}, fun(_,_) -> [fun() -> par_run(2000,2000,1) end] end}
       %% , {[{rate,100},
       %% 	   {group,50}], fun(O,_) -> [fun() -> max_rate_test(O,1) end] end}
       , {{count,3}, fun(_,_) -> [fun() -> counter_run(30,1) end] end}
       , {{timeout,500}, fun(_,_) -> [fun() ->
					      ?debugVal(timeout_test(500))
				      end] end}
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

timeout_test(T) ->
    case timer:tc(jobs, ask, [q]) of
	{US, {error, timeout}} ->
	    case (US div 1000) - T of
		Diff when Diff < 5 ->
		    ok;
		Other ->
		    error({timeout_too_late, Other})
	    end;
	Other ->
	    error({timeout_expected, Other})
    end.

time_eval(_R, _N, T, Ts, Expected) ->
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



%% counter_test(Count) ->
%%     start_test_server({count,Count}),
%%     Res = tc(fun() ->
%% 		     pmap(fun() -> jobs:run(q, one_job(count)) end, Count * 2)
%% 	     end),
%%     io:fwrite(user, "~p~n", [Res]),
%%     stop_server().


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

start_test_server(Conf) ->
    start_test_server(true, Conf).

start_test_server(Silent, {rate,Rate}) ->
    start_with_conf(Silent, [{queues, [{q, [{regulators,
					     [{rate,[
						     {limit, Rate}]
					      }]}
					    %% , {mod, jobs_queue_list}
					   ]}
				      ]}
			    ]),
    Rate;
start_test_server(Silent, [{rate,Rate},{group,Grp}]) ->
    start_with_conf(Silent,
		    [{group_rates, [{gr, [{limit, Grp}]}]},
		     {queues, [{q, [{regulators,
				     [{rate,[{limit, Rate}]},
				      {group_rate, gr}]}
				   ]}
			      ]}
		    ]),
    Grp;
start_test_server(Silent, {count, Count}) ->
    start_with_conf(Silent,
		    [{queues, [{q, [{regulators,
				     [{counter,[
						{limit, Count}
					       ]
				      }]}
				   ]}
			      ]}
		    ]);
start_test_server(Silent, {timeout, T}) ->
    start_with_conf(Silent,
		    [{queues, [{q, [{regulators,
				     [{counter,[
						{limit, 0}
					       ]}
				     ]},
				    {max_time, T}
				   ]}
			      ]}
		    ]).


start_with_conf(Silent, Conf) ->
    application:unload(jobs),
    application:load(jobs),
    [application:set_env(jobs, K, V) ||	{K,V} <- Conf],
    if Silent == true ->
	    error_logger:delete_report_handler(error_logger_tty_h);
       true ->
	    ok
    end,
    application:start(jobs).


stop_server() ->
    application:stop(jobs).

tc(F) ->
    T1 = os:timestamp(),
    R = (catch F()),
    T2 = os:timestamp(),
    {timer:now_diff(T2,T1), R}.

run_jobs(Q,N) ->
    [run_job(Q, one_job(time)) || _ <- lists:seq(1,N)].

run_job(Q,F) ->
    timer:tc(jobs,run,[Q,F]).

one_job(time) ->
    fun timestamp/0;
one_job(count) ->
    fun() ->
	    1
    end.


timestamp() ->
    jobs_server:timestamp().
