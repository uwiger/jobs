-module(t).

-compile(export_all).

t() ->
    eqc:module([{numtests, 1000}], jobs_eqc_queue).
