DIALYZER=dialyzer

.PHONY: all test clean plt analyze doc test-console

all: deps compile

deps:
	rebar get-deps

compile:
	rebar compile

test: all
	rebar eunit

clean:
	rebar clean

doc:
	rebar doc

test-console:
	erl -pa deps/*/ebin ebin

plt: deps compile
	$(DIALYZER) --build_plt --output_plt .jobs.plt \
		-pa deps/*/ebin \
		deps/*/ebin \
		--apps kernel stdlib sasl inets crypto \
		public_key ssl runtime_tools erts \
		compiler tools syntax_tools hipe webtool

analyze: compile
	$(DIALYZER) --no_check_plt \
		     ebin \
		--plt .jobs.plt

