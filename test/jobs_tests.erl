-module(jobs_tests).

-compile(export_all).

-include_lib("eunit/include/eunit.hrl").



msg_test_() ->
    Rate = 100,
    {foreach,
     fun() -> with_msg_sampler(Rate) end,
     fun(_) -> stop_jobs() end,
     [
      {with, [fun apply_feedback/1]}
     ]}.

dist_test_() ->
    Rate = 100,
    Name = jobs_eunit_slave,
    {foreach,
     fun() ->
	     ?assertEqual(Rate, with_msg_sampler(Rate)),
	     Remote = start_slave(Name),
	     ?assertEqual(Rate,
			  rpc:call(Remote, ?MODULE, with_msg_sampler, [Rate])),
	     {Remote, Rate}
     end,
     fun({Remote, _}) ->
	     Res = rpc:call(Remote, erlang, halt, []),
	     io:fwrite(user, "Halting remote: ~p~n", [Res]),
	     stop_jobs()
     end,
     [
      {with, [fun apply_feedback/1]}
     ]}.
	     


with_msg_sampler(Rate) ->
    application:unload(jobs),
    ok = application:load(jobs),
    [application:set_env(jobs, K, V) ||
	{K,V} <- [{queues, [{q, [{regulators, 
				  [{rate, [
					   {limit, Rate},
					   {modifiers,
					    [{test,10, {max,5}}]}]}]}
				]}
			   ]},
		  {samplers, [{test, jobs_sampler_slave,
			       {value, [{1,1},{2,2},{3,3}]}}
			     ]}
		 ]
    ],
    ok = application:start(jobs),
    Rate.

start_slave(Name) ->
    case node() of
	nonode@nohost ->
	    os:cmd("epmd -daemon"),
	    {ok, _} = net_kernel:start([jobs_eunit_master, shortnames]);
	_ ->
	    ok
    end,
    {ok, Node} = slave:start(host(), Name, "-pa . -pz ../ebin"),
    io:fwrite(user, "Slave node: ~p~n", [Node]),
    Node.

host() ->
    [Name, Host] = re:split(atom_to_list(node()), "@", [{return, list}]),
    list_to_atom(Host).


stop_jobs() ->
    dbg:stop(),
    application:stop(jobs).

apply_feedback(Rate) when is_integer(Rate) ->
    ?assertEqual(R0=get_rate(), Rate),
    io:fwrite(user, "R0 = ~p~n", [R0]),
    kick_sampler(1),
    io:fwrite(user, "get_rate() -> ~p~n", [get_rate()]),
    ?assertEqual(get_rate(), Rate - 10),
    kick_sampler(2),
    io:fwrite(user, "get_rate() -> ~p~n", [get_rate()]),
    ?assertEqual(get_rate(), Rate - 20),
    kick_sampler(3),
    io:fwrite(user, "get_rate() -> ~p~n", [get_rate()]),
    ?assertEqual(get_rate(), Rate - 30);
apply_feedback({Remote, Rate}) ->
    ?assertEqual(R0=get_rate(), Rate),
    io:fwrite(user, "R0 = ~p~n", [R0]),
    ?assertEqual(rpc:call(Remote,?MODULE,get_rate,[]), Rate),
    kick_sampler(Remote, 1),
    io:fwrite(user, "[Remote] get_rate() -> ~p~n", [get_rate()]),
    ?assertEqual(get_rate(), Rate - 5),
    kick_sampler(Remote, 2),
    io:fwrite(user, "[Remote] get_rate() -> ~p~n", [get_rate()]),
    ?assertEqual(get_rate(), Rate - 10),
    kick_sampler(Remote, 3),
    io:fwrite(user, "[Remote] get_rate() -> ~p~n", [get_rate()]),
    ?assertEqual(get_rate(), Rate - 15).
    
    
get_rate() ->
    jobs:queue_info(q, rate_limit).

kick_sampler(N) ->
    jobs_sampler ! {test, log, N},
    timer:sleep(1000).


kick_sampler(Remote, N) ->
    io:fwrite("Kicking sampler (N=~p) at ~p~n", [N, Remote]),
    {jobs_sampler, Remote} ! {test, log, N},
    timer:sleep(1000).

