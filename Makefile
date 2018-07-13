REBAR3=$(shell which rebar3 || echo ./rebar3)

.PHONY: all test clean doc dialyzer

all: compile

compile:
	$(REBAR3) compile

test: all
	$(REBAR3) eunit

clean:
	$(REBAR3) clean

doc:
	$(REBAR3) doc

dialyzer:
	$(REBAR3) dialyzer
