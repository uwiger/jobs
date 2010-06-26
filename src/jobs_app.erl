-module(jobs_app).

-export([start/2, stop/1,
         init/1]).


start(_, _) ->
    supervisor:start_link({local,?MODULE},?MODULE,[]).

stop(_) ->
    ok.


init([]) ->
    {ok, {{rest_for_one,3,10},
          [{jobs_server, {jobs_server,start_link,[]},
            permanent, 3000, worker, [jobs_server]}|
           sampler_spec()]}}.


sampler_spec() ->
    Mod = case application:get_env(sampler) of
              {ok,M} when M =/= undefined -> M;
              _ -> jobs_sampler
          end,
    [{jobs_sampler, {Mod,start_link,[]}, permanent, 3000, worker, [Mod]}].

            
