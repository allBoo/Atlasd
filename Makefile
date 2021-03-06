
all: compile ctl

compile:
	./scripts/share_includes.sh
	./scripts/rebar co
	cp etc/app.config rel/files/sys.config
	cp etc/atlasd.yml rel/files/

ctl:
	cd src/atlasctl/ && ../../scripts/rebar escriptize
	mv src/atlasctl/atlasctl .
	cp atlasctl rel/files/

rc: clean compile ctl

recompile: clean compile ctl

clean:
	./scripts/rebar clean

includes:
	./scripts/share_includes.sh

gd:
	./scripts/rebar g-d
