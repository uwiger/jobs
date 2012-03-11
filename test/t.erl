-module(t).

-compile(export_all).

t() ->
    jobs_eqc_queue:test().
