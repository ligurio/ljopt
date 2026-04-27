local dev_checks = require("ljopt.dev_checks")
local ffi = require("ffi")

local is64 = ffi.abi("gc64")
local sz = is64 and 64 or 32

ffi.cdef(([[
typedef struct GCRef {
  uint%d_t gcptr;
} GCRef;

typedef struct MRef {
  uint%d_t ptr;
} MRef;

typedef struct GCtab {
  GCRef nextgc; uint8_t marked; uint8_t gct;

  uint8_t nomm;		/* Negative cache for fast metamethods. */
  int8_t colo;		/* Array colocation. */
  MRef array;		/* Array part. */
  GCRef gclist;
  GCRef metatable;	/* Must be at same offset in GCudata. */
  MRef node;		/* Hash part. */
  uint32_t asize;	/* Size of array part (keys [0, asize-1]). */
  uint32_t hmask;	/* Hash part mask (size of hash part - 1). */
  MRef freetop;		/* Top of free elements. */
} GCtab;
]]):format(sz, sz))

local function tablesize(tab)
    dev_checks("table")
    local gctab = ffi.cast("GCtab *", tonumber(string.format("%p", tab)))
    return tonumber(gctab.hmask), tonumber(gctab.asize)
end

return {
    tablesize = tablesize,
}
