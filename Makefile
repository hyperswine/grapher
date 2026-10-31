.PHONY: all test desktop gui-check frame-check

SOL ?= sol
SOL_ENV = SOL_CACHE_DIR="$(CURDIR)/.cache/sol" SOL_STATE_DIR="$(CURDIR)/.cache/sol-state"

all: build/grapher

build/grapher: cli/main.fpr cli/features.fpr lib/points.fpr
	mkdir -p build .cache
	XDG_CACHE_HOME="$(CURDIR)/.cache" fpr build cli/main.fpr -o build/grapher

test: build/grapher
	mkdir -p .cache/sol .cache/sol-state
	$(SOL_ENV) $(SOL) tests/check.sol

desktop:
	mkdir -p build
	qos build desktop
	test -f build/grapher.disk || qos disk create build/grapher.disk
	qos install desktop/build/grapher.qa build/grapher.disk
	qos run build/grapher.disk

gui-check:
	qos build desktop
	mkdir -p .cache/sol .cache/sol-state
	$(SOL_ENV) $(SOL) tests/gui.sol

frame-check:
	mkdir -p .cache/sol .cache/sol-state
	$(SOL_ENV) $(SOL) tests/frames.sol
