FROM node:22-bookworm

# ── system deps ──────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake git ca-certificates \
        luarocks z3 \
    && rm -rf /var/lib/apt/lists/*

# ── ljopt ────────────────────────────────────────────────────────
WORKDIR /opt/ljopt
COPY . /opt/ljopt/

ARG LUAJIT_TAG=af5d38f109b6a7f714b41f92a57e2bd67d14955a
RUN git clone https://github.com/tarantool/luajit build/luajit_${LUAJIT_TAG} \
    && cd build/luajit_${LUAJIT_TAG} \
    && git reset --hard ${LUAJIT_TAG} \
    && git apply /opt/ljopt/lua_patches/*.patch \
    && cmake -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
             -DCMAKE_BUILD_TYPE=RelWithDebInfo \
             -DCMAKE_INSTALL_PREFIX=/opt/ljopt/build/luajit_${LUAJIT_TAG} \
    && make install

RUN luarocks install --local checks

# ── wrapper script ───────────────────────────────────────────────
COPY CE/ljopt-ce.sh /opt/ljopt/ljopt-ce.sh
RUN chmod +x /opt/ljopt/ljopt-ce.sh

# ── compiler explorer ────────────────────────────────────────────
WORKDIR /opt/compiler-explorer
ARG CE_VERSION=532bbe62b6a1aba3d3c7527576268d4d08e0ca11
RUN git clone --depth 50 https://github.com/compiler-explorer/compiler-explorer.git . \
    && git checkout ${CE_VERSION}

# Apply lua language patch
COPY CE/ce-lua-language.patch /tmp/ce-lua-language.patch
RUN git apply /tmp/ce-lua-language.patch

# Lua example
RUN mkdir -p examples/lua
COPY CE/default.lua examples/lua/default.lua

# Compiler properties
COPY CE/lua.defaults.properties etc/config/lua.defaults.properties

# Install CE deps
RUN npm ci

EXPOSE 10240
CMD ["npx", "tsx", "./app.ts", "--language", "lua"]
