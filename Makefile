# This way everything works as expected ever for
# `make -C /path/to/project` or
# `make -f /path/to/project/Makefile`.
MAKEFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
PROJECT_DIR := $(patsubst %/,%,$(dir $(MAKEFILE_PATH)))

LUACOV_REPORT := $(PROJECT_DIR)/luacov.report.out
LUACOV_STATS := $(PROJECT_DIR)/luacov.stats.out

LUA_PATH_ROCKS=$(shell luarocks path --lr-path)
LUA_PATH="${LUA_PATH_ROCKS};./?/init.lua;;"

# Don't forget to update the commit hash in .envrc.
LUAJIT_TAG ?= af5d38f109b6a7f714b41f92a57e2bd67d14955a
LUAJIT_BUGGY_TAG ?= 203a98682e925d3740291db26184b8a847857943~
# Extra flags passed to CMake when building LuaJIT, e.g.
# `-DLUAJIT_NUMMODE=2` to build a DUALNUM variant.
LUAJIT_CMAKE_FLAGS ?=
BUILD_DIR := $(PROJECT_DIR)/build
LUA_BIN := $(BUILD_DIR)/luajit_$(LUAJIT_TAG)/src/luajit
LUA_BUGGY_BIN := $(BUILD_DIR)/luajit_$(LUAJIT_BUGGY_TAG)/src/luajit

CLEANUP_FILES  = ${LUACOV_STATS}
CLEANUP_FILES += ${LUACOV_REPORT}
CLEANUP_FILES += ${BUILD_DIR}

all: check test


# @1 - commit to build LuaJIT on
# @2 - extra CMake flags (e.g. -DLUAJIT_NUMMODE=2 for DUALNUM)
define build_luajit
	@if [ ! -d "$(BUILD_DIR)/luajit_$(1)" ]; then \
		git clone https://github.com/tarantool/luajit $(BUILD_DIR)/luajit_$(1); \
	fi
	@cd $(BUILD_DIR)/luajit_$(1) && \
		echo "Reset to $(1)..." && \
		git reset --hard $(1) && \
		echo "Applying patches..." && \
		git apply $(PROJECT_DIR)/lua_patches/*.patch && \
		cmake -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=$(BUILD_DIR)/luajit_$(1) $(2) && \
		echo "Building..." && \
		$(MAKE) install
endef

$(LUA_BIN):
	@echo "Building LuaJIT $(LUAJIT_TAG)"
	$(call build_luajit,$(LUAJIT_TAG),$(LUAJIT_CMAKE_FLAGS))

$(LUA_BUGGY_BIN):
	@echo "Building buggy LuaJIT $(LUAJIT_BUGGY_TAG)"
	$(call build_luajit,$(LUAJIT_BUGGY_TAG),$(LUAJIT_CMAKE_FLAGS))

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

test: $(LUA_BUGGY_BIN) $(LUA_BIN)
	@echo "Run regression tests"
	LUA_PATH=$(LUA_PATH) $(LUA_BIN) $(PROJECT_DIR)/tests/tests.lua
	@echo "Run unit tests"
	LUA_PATH=$(LUA_PATH) $(LUA_BIN) $(PROJECT_DIR)/tests/unit_tests.lua
	LUA_PATH=$(LUA_PATH) $(LUA_BIN) $(PROJECT_DIR)/tests/ir_tests.lua
	$(MAKE) test-buggy

test-buggy: $(LUA_BUGGY_BIN) $(LUA_BIN)
	@echo "Run buggy LuaJIT tests on old version"
	BUGGY_BUILD=1 LUA_PATH=$(LUA_PATH) $(LUA_BUGGY_BIN) $(PROJECT_DIR)/tests/buggy_luajit_tests.lua
	@echo "Run buggy LuaJIT tests on current version"
	LUA_PATH=$(LUA_PATH) $(LUA_BIN) $(PROJECT_DIR)/tests/buggy_luajit_tests.lua

$(LUACOV_STATS):
	LJOPT_COVERAGE=1 $(MAKE) test

# Cheap check that the z3 backend still works.
test-z3-smoke: $(LUA_BIN)
	@echo "Smoke-test the z3 backend"
	LJOPT_SMT=z3 LUA_PATH=$(LUA_PATH) $(LUA_BIN) $(PROJECT_DIR)/tests/ir_tests.lua

coverage: $(LUACOV_STATS)
	@sed -i -e 's@'"$$(realpath .)"'/@@' $(LUACOV_STATS)
	@cd $(PROJECT_DIR) && luacov ^ljopt
	@grep -A999 '^Summary' $(LUACOV_REPORT)

clean:
	@rm -rf ${CLEANUP_FILES}

.PHONY: test test-buggy install coverage
.PHONY: luacheck check deps
