all:
	@./rebar get-deps compile

test: all
	@./rebar eunit

clean:
	@./rebar clean

