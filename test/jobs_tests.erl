-module(jobs_tests).

-compile(export_all).

-include_lib("eunit/include/eunit.hrl").



msg_test_() ->
    Rate = 100,
    {foreach,
     fun() -> with_msg_sampler(Rate) end,
     fun stop_jobs/1,
     [
      fun apply_feedback/1
     ]}.


with_msg_sampler(Rate) ->
    application:unload(jobs),
    application:load(jobs),
    [application:set_env(jobs, K, V) ||
	{K,V} <- [{queues, [{q, [{regulators, 
				  [{rate, [
					   {limit, Rate},
					   {modifiers,
					    [{test,10}]}]}]}
				]}
			   ]},
		  {samplers, [{test, jobs_sampler_slave,
			       {value, [{1,1},{2,2},{3,3}]}}
			     ]}
		 ]
    ],
    application:start(gproc),
    application:start(jobs),
    Rate.

stop_jobs(_) ->
    application:stop(jobs),
    application:stop(gproc).

apply_feedback(Rate) ->
    ?assertEqual(get_rate(), Rate),
    kick_sampler(1),
    io:fwrite(user, "get_rate() -> ~p~n", [get_rate()]),
    ?assertEqual(get_rate(), Rate - 10),
    kick_sampler(2),
    io:fwrite(user, "get_rate() -> ~p~n", [get_rate()]),
    ?assertEqual(get_rate(), Rate - 20),
    kick_sampler(3),
    io:fwrite(user, "get_rate() -> ~p~n", [get_rate()]),
    ?assertEqual(get_rate(), Rate - 30).
    
get_rate() ->
    jobs:queue_info(q, rate_limit).

kick_sampler(N) ->
    jobs_sampler ! {test, log, N},
    timer:sleep(1000).

