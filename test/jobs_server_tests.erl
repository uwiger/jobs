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
       , {[{rate,5},{count,3}],
          fun(_,_) -> [fun() -> par_run(5,5,1) end] end}
       , {{timeout,500}, fun(_,_) -> [fun() ->
                                              ?debugVal(timeout_test(500))
                                      end] end}
      ]}.


config_test_() ->
    {foreachx,
     fun(Conf) -> start_server_w_config(Conf) end,
     fun(_, _) -> stop_server() end,
     [ {#{ restore => {true, preset}
         , preset => [{queue,q}]
         , dynamic => [{queue,q1}]}, fun config_test_f/2}
     , {#{ restore => {false, preset}
         , preset => [{queue,q}]
         , dynamic => [{queue,q1}] }, fun config_test_f/2}
     , {#{ restore => {true, preset}
         , preset => []
         , dynamic => [{queue,q1,[{standard_rate,100}]}] }, fun rate_recovers/2}
     ]}.

config_test_f(Conf, Pre) ->
    fun() ->
            restart_jobs_server(),
            compare_configs(Pre, prune_info(jobs:info(all)), Conf)
    end.

rate_recovers(#{dynamic := [{queue,Q,[{standard_rate,R}]}]} = _Conf, _Pre) ->
    fun() ->
            true = test_rate(Q, R),
            restart_jobs_server(),
            true = test_rate(Q, R)
    end.

restart_jobs_server() ->
    exit(whereis(jobs_server), kill),
    await_jobs_server(1000).

test_rate(Q, R) ->
            T0 = jobs_lib:timestamp(),
            Times = [jobs:run(Q, fun() ->
                                         jobs_lib:timestamp()
                                  end) || _ <- lists:seq(1,10)],
    TimeLimit = 1000 * 10 * (1/R), % in milliseconds
    Actual = (lists:last(Times) - T0),
    %% allow for 10% deviation
    {true, _} = {Actual =< (TimeLimit * 1.1),
                 {TimeLimit, Actual, T0, Times}},
    true.


start_server_w_config(Conf) ->
    ensure_jobs_cleared(),
    application:load(jobs),
    set_env_w_config(Conf),
    application:ensure_started(jobs),
    post_start_config(Conf),
    apply_dynamic(maps:get(dynamic, Conf, [])),
    prune_info(jobs:info(all)).

ensure_jobs_cleared() ->
    application:stop(jobs),
    application:unload(jobs).

set_env_w_config(#{preset := Preset, restore := {Restore, Ctxt}}) ->
    Queues = [{Q, [{standard_rate,2}]} || {queue, Q} <- Preset],
    application:set_env(jobs, queues, Queues),
    [application:set_env(jobs, auto_restore, Restore) || Ctxt == preset],
    ok.

post_start_config(#{restore := {Restore, dynamic}}) ->
    jobs_server:auto_restore(Restore);
post_start_config(_) ->
    ok.

apply_dynamic(Dyn) ->
    lists:foreach(
      fun({queue, Q}) ->
              ok = jobs:add_queue(Q, [{standard_rate, 2}]);
         ({queue, Q, Opts}) ->
              ok = jobs:add_queue(Q, Opts)
      end, Dyn).

await_jobs_server(Timeout) ->
    TRef = erlang:start_timer(Timeout, self(), await_jobs_server),
    await_jobs_server_(TRef).

await_jobs_server_(TRef) ->
    case whereis(jobs_server) of
        undefined ->
            receive
                {timeout, TRef, await_jobs_server} ->
                    erlang:error(timeout)
            after 10 ->
                    await_jobs_server_(TRef)
            end;
        Pid when is_pid(Pid) ->
            case is_process_alive(Pid) of
                true ->
                    erlang:cancel_timer(TRef),
                    Pid;
                false ->
                    await_jobs_server_(TRef)
            end
    end.

prune_info(Info) ->
    lists:map(fun prune_info_/1, Info).

prune_info_({queues, Qs}) ->
    {queues, [{Q, prune_q_info(Iq)} || {Q, Iq} <- Qs]};
prune_info_(I) ->
    I.

prune_q_info(I) ->
    [X || {K,_} = X <- I,
          not lists:member(K, [check_interval,
                               latest_dispatch, approved, queued,
                               oldest_job, timer, empty, depleted,
                               waiters, stateful, st])].

compare_configs(_, _, #{restore := {false,_}}) -> true;
compare_configs(I1, I2, Conf) ->
    {I1, I2, _} = {I2, I1, Conf}.

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
                                     [reg({count, Count})]
                                    }]
                               }]
                     }]);
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
		    ]);
start_test_server(Silent, [_|_] = Rs) ->
    start_with_conf(Silent,
                    [{queues, [{q,
                                [{regulators, [reg(R) || R <- Rs]}]
                               }]
                     }]).


reg({rate, R}) ->
    {rate, [{limit, R}]};
reg({count, C}) ->
    {counter, [{limit, C}]}.



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
    T1 = jobs_lib:time_compat(),
    R = (catch F()),
    T2 = jobs_lib:time_compat(),
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
