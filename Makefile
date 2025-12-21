# This way everything works as expected ever for
# `make -C /path/to/project` or
# `make -f /path/to/project/Makefile`.
MAKEFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
PROJECT_DIR := $(patsubst %/,%,$(dir $(MAKEFILE_PATH)))

LUACOV_REPORT := $(PROJECT_DIR)/luacov.report.out
LUACOV_STATS := $(PROJECT_DIR)/luacov.stats.out

LUA_PATH_ROCKS=$(shell luarocks path --lr-path)
LUA_PATH="${LUA_PATH_ROCKS};./?/init.lua;;"

LUAJIT_DIR := $(PROJECT_DIR)/luajit
LUA_BIN ?= $(LUAJIT_DIR)/tarantool_luajit/bin/luajit
LUAJIT_TAG ?= af5d38f109b6a7f714b41f92a57e2bd67d14955a

CLEANUP_FILES  = ${LUACOV_STATS}
CLEANUP_FILES += ${LUACOV_REPORT}
CLEANUP_FILES += ${LUAJIT_DIR}

all: check test

$(LUA_BIN):
	@echo "Building LuaJIT..."
	@if [ ! -d "$(LUAJIT_DIR)" ]; then \
		git clone https://github.com/tarantool/luajit $(LUAJIT_DIR); \
	fi
	# Install 2.1.0-beta3 tarantool's LuaJIT.
	@cd $(LUAJIT_DIR) && \
		echo "Reset to $(LUAJIT_TAG)..." && \
		git reset --hard $(LUAJIT_TAG) && \
		echo "Applying patches..." && \
		git apply ../lua_patches/*.patch && \
		cmake -Bbuild -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=tarantool_luajit && \
		echo "Building luajit..." && \
		cmake --build build --target install

build: $(LUA_BIN)

deps:
	@echo "Setup dependencies"
	@luarocks install --local checks
	@luarocks install --local luacheck 0.25.0
	@luarocks install --local luacov 0.15.0

install:
	@install -d -m 755 $(LUADIR)/ljopt
	@install -m 644 $(PROJECT_DIR)/ljopt/*.lua $(LUADIR)/ljopt

check: luacheck lint

luacheck:
	@luacheck --config $(PROJECT_DIR)/.luacheckrc --codes $(PROJECT_DIR)

lint:
	@luarocks lint ljopt-scm-1.rockspec

test: $(LUA_BIN)
	@echo "Run regression tests"
	LUA_PATH=$(LUA_PATH) $(LUA_BIN) $(PROJECT_DIR)/tests/tests.lua
	@echo "Run unit tests"
	LUA_PATH=$(LUA_PATH) $(LUA_BIN) $(PROJECT_DIR)/tests/unit_tests.lua

$(LUACOV_STATS):
	LJOPT_COVERAGE=1 $(MAKE) test

coverage: $(LUACOV_STATS)
	@sed -i -e 's@'"$$(realpath .)"'/@@' $(LUACOV_STATS)
	@cd $(PROJECT_DIR) && luacov ^ljopt
	@grep -A999 '^Summary' $(LUACOV_REPORT)

clean:
	@rm -rf ${CLEANUP_FILES}

.PHONY: test install coverage
.PHONY: luacheck check deps
