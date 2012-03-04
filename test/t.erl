-module(t).

-compile(export_all).

t() ->
    eqc:module(jobs_eqc_queue).
