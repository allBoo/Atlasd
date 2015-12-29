
all: compile ctl

compile:
	./scripts/rebar co

ctl:
	cd src/atlasctl/ && ../../scripts/rebar escriptize
	mv src/atlasctl/atlasctl .
	cp atlasctl rel/files/

includes:
	./scripts/share_includes.sh

gd:
	./scripts/rebar g-d
