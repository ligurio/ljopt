# This way everything works as expected ever for
# `make -C /path/to/project` or
# `make -f /path/to/project/Makefile`.
MAKEFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
PROJECT_DIR := $(patsubst %/,%,$(dir $(MAKEFILE_PATH)))

LUACOV_REPORT := $(PROJECT_DIR)/luacov.report.out
LUACOV_STATS := $(PROJECT_DIR)/luacov.stats.out

CLEANUP_FILES  = ${LUACOV_STATS}
CLEANUP_FILES += ${LUACOV_REPORT}

LUA_BIN ?= /usr/bin/lua

all: check test

doc:
	@ldoc -c $(PROJECT_DIR)/doc/config.ld -v \
              -d $(PROJECT_DIR)/doc/html/ \
                 $(PROJECT_DIR)/luamut

deps:
	@echo "Setup dependencies"
	@luarocks install --local cluacov 0.1.1
	@luarocks install --local ldoc 1.5.0
	@luarocks install --local luacheck 0.25.0
	@luarocks install --local luacov 0.15.0
	@luarocks install --local luacov-coveralls 0.2.3

install:
	@install -d -m 755 $(LUADIR)/luamut
	@install -m 644 $(PROJECT_DIR)/luamut/*.lua $(LUADIR)/luamut

check: luacheck

luacheck:
	@luacheck --config $(PROJECT_DIR)/.luacheckrc --codes $(PROJECT_DIR)

test:
	@echo "Run regression tests"
	$(LUA_BIN) $(PROJECT_DIR)/tests/tests.lua

$(LUACOV_STATS): test

coverage: $(LUACOV_STATS)
	@sed -i -e 's@'"$$(realpath .)"'/@@' $(LUACOV_STATS)
	@cd $(PROJECT_DIR) && luacov ^luamut
	@grep -A999 '^Summary' $(LUACOV_REPORT)

coveralls: coverage
	@echo "Send code coverage data to the coveralls.io service"
	@luacov-coveralls --include ^luamut --verbose --repo-token ${GITHUB_TOKEN}

test-corpus: clean
	@find corpus/static/ -name '*.lua' -print0 | xargs -0 -n1 -i ${LUA_BIN} {}

clean:
	@rm -rf ${CLEANUP_FILES}

.PHONY: test install coveralls coverage
.PHONY: luacheck check doc deps
