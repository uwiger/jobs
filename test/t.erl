-module(t).

-compile(export_all).

t() ->
    eqc:module([{numtests, 300}], jobs_eqc_queue).
