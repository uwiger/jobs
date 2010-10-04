-module(jobs_server_tests).


-export([rate_test/1,
	 serial_run/1,
	 parallel_run/1,
	 counter_test/1,
	 start_test_server/1,
	 stop_server/0]).

-include_lib("eunit/include/eunit.hrl").



rate_test_() ->
    [fun() -> rate_test(R) end || R <- [1,5,10,100]]
	++ [fun() -> max_rate_test(R) end || R <- [400,600,1000,1500]]
	++ [fun() -> counter_test(C) end || C <- [1,5,10]]
	++ [fun() -> group_rate_test(R) end || R <- [10,50,100]].
		    

rate_test(Rate) ->
    start_test_server({rate,Rate}),
    serial_run(Rate),
    stop_server().

max_rate_test(Rate) ->
    start_test_server({rate,Rate}),
    parallel_run(Rate),
    stop_server().

serial_run(N) ->
    Res = tc(fun() -> run_jobs(q,N) end),
    io:fwrite(user, "Rate: ~p, Res = ~p~n", [N,Res]).

parallel_run(N) ->
    Res = tc(fun() -> pmap(fun() ->
				   jobs:run(q, one_job(time))
			   end, N)
	     end),
    io:fwrite(user, "Rate: ~p, Res = ~p~n", [N,Res]).
    
		      


counter_test(Count) ->
    start_test_server({count,Count}),
    Res = tc(fun() ->
		     pmap(fun() -> jobs:run(q, one_job(count)) end, Count * 2)
	     end),
    io:fwrite(user, "~p~n", [Res]),
    stop_server().

group_rate_test(Rate) ->
    start_test_server([{rate,Rate * 2},{group,Rate}]),
    serial_run(Rate),
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
    jobs_server:start_link([{queues, [{q, [{regulators,
					    [{rate,[
						    {limit, Rate}]
					     }]}
					   %% , {mod, jobs_queue_list}
					  ]}
				     ]}
			   ]);
start_test_server([{rate,Rate},{group,Grp}]) ->
    jobs_server:start_link([{group_rates, [{gr, [{limit, Grp}]}]},
			    {queues, [{q, [{regulators,
					    [{rate,[{limit, Rate}]},
					     {group_rate, gr}]}
					  ]}
				     ]}
			   ]);
start_test_server({count, Count}) ->
    application:start(gproc),
    jobs_server:start_link([{queues, [{q, [{regulators,
					    [{counter,[
						       {limit, Count}
						      ]
					     }]}
					  ]}
				     ]}
			   ]).


stop_server() ->
    unlink(whereis(?MODULE)),
    Ref = erlang:monitor(process, ?MODULE),
    exit(whereis(?MODULE), done),
    %% make sure it's really down before returning:
    receive {'DOWN',Ref,_,_,_} ->
            ok
    end.


tc(F) ->
    T1 = erlang:now(),
    R = (catch F()),
    T2 = erlang:now(),
    {timer:now_diff(T2,T1), R}.

run_jobs(Q,N) ->
    [jobs:run(Q, one_job(time)) || _ <- lists:seq(1,N)].

one_job(time) ->
    fun timestamp/0;
one_job(count) ->
    fun() ->
	    gproc:select(a,[{{{'_',l,'$1'},'_','$2'},[],[{{'$1','$2'}}]}])
    end.


timestamp() ->
    jobs_server:timestamp().
