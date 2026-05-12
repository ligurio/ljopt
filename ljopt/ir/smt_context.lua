--[[
Provides different types of stacks for IR. Data stored in stacks
is used for checking if two IR traces are equivalent.
]]--

local utils = require('ljopt.utils')
local op_type = require('ljopt.ir.op_type')
local smt_constants = require('ljopt.smt_constants')

local dev_checks = require('ljopt.dev_checks')

local function extended(child, parent)
    dev_checks('table', 'table')

    setmetatable(child, { __index = parent })
end

local type2bv = {
    ['tab'] = '%s',
    ['flt'] = '(fp.to_ieee_bv %s)',
    ['i8']  = '%s',
    ['u8']  = '%s',
    ['i16'] = '%s',
    ['u16'] = '%s',
    ['u32'] = '%s',
    ['int'] = '%s',
    ['u64'] = '%s',
    ['i64'] = '%s',
    ['p32'] = '%s',
    ['p64'] = '%s',
    [op_type.STR] = '%s',
    [op_type.ANY] = '%s',
    ['num'] = '%s',
}

local bv2type = {
    ['tab'] = '%s',
    ['flt'] = '((_ to_fp 9 24) %s)',
    ['i8']  = '%s',
    ['u8']  = '%s',
    ['i16'] = '%s',
    ['u16'] = '%s',
    ['u32'] = '%s',
    ['int'] = '%s',
    ['u64'] = '%s',
    ['i64'] = '%s',
    ['p32'] = '%s',
    ['p64'] = '%s',
    [op_type.STR] = '%s',
    [op_type.ANY] = '%s',
    ['num'] = '%s',
}


local StackBase = {}
function StackBase:new()
    local public = {}

    function StackBase.init_smt( --[[name]])
    end

    function StackBase.load( --[[slot_num, type]])
    end

    function StackBase.store( --[[slot_num, type, data]])
    end

    setmetatable(public, self)
    self.__index = self;
    return public
end

local function create_value(memcell, type)
    if type == op_type.STR then
        return ('(str-val %s)'):format(memcell)
    elseif type == op_type.ANY then
        return memcell
    elseif type == 'num' then
        return ('(fp-val %s)'):format(memcell)
    elseif type == 'tab' then
        return ('(tab-val %s)'):format(memcell)
    else
        return ('(int-val %s)'):format(memcell)
    end
end

local function extract_value(memcell, type)
    if type == op_type.ANY then
        return memcell
    elseif type == op_type.STR then
        return ('(get-str %s)'):format(memcell)
    elseif type == 'num' then
        return ('(get-fp %s)'):format(memcell)
    elseif type == 'tab' then
        return ('(get-tab %s)'):format(memcell)
    else
        return ('(get-bv %s)'):format(memcell)
    end
end

local VMStackBV = {}
extended(VMStackBV, StackBase)

function VMStackBV.init_smt(self, name)
    dev_checks('table', 'string')

    self._name = name
    self._cur_stack = 0
    return string.format(
        '(declare-fun %s () (Array Int (Array Int (MemCell))))', name
    )
end

function VMStackBV.load(self, slot_num, type)
    dev_checks('table', 'number', 'string')

    local stack = string.format('(select %s %d)', self._name, self._cur_stack)
    local slot = string.format('(select %s %d)', stack, slot_num)
    local conv
    if bv2type[type] == nil then
        return ''
    else
        conv = assert(bv2type[type], 'Unsupported load type ' .. type)
    end
    return string.format(conv, extract_value(slot, type))
end

function VMStackBV.store(self, slot_num, type, data)
    dev_checks('table', 'number', 'string', 'string')

    local conv = assert(type2bv[type], 'Unsupported load op type ' .. type)
    local conv_data = string.format(conv, data)
    local stack = string.format(
        '(select %s %d)', self._name, self._cur_stack
    )
    local new_stack = string.format(
        '(store %s %d %s)', stack, slot_num, conv_data
    )
    self._cur_stack = self._cur_stack + 1
    local new_location = string.format(
        '(select %s %d)', self._name, self._cur_stack
    )
    return string.format('(assert (= %s %s))', new_location, new_stack)
end

local OpStackBV = {}
extended(OpStackBV, StackBase)

function OpStackBV.init_smt(self, name)
    dev_checks('table', 'string')

    self._name = name
    return string.format(
        '(declare-fun %s () (Array Int MemCell))\n',
        self._name
    )
end

function OpStackBV.load(self, op_num, type)
    dev_checks('table', 'number', 'string')

    assert(op_num >= 0,
        'Index is negative, something weird happening: ' .. op_num
    )
    local conv = assert(bv2type[type], 'Unsupported load op type ' .. type)
    local val = string.format('(select %s %d)', self._name, op_num)
    return string.format(conv, extract_value(val, type))
end

function OpStackBV.store(self, op_num, type, data)
    dev_checks('table', 'number', 'string', 'string')

    assert(op_num >= 0,
        'Index is negative, something weird happening: ' .. op_num
    )
    if data == '' then
        return ''
    end
    local conv = assert(type2bv[type], 'Unsupported store op type ' .. type)
    return string.format(
        '(assert (let ((a!1 %s)) (= (select %s %d) a!1)))',
        create_value(string.format(conv, data), type),
        self._name,
        op_num
    )
end

-- Below is the description of how TEStack works and
-- how we verify guarded asserions.
--
-- Some instructions are guarded assertions (EQ, ADDOV, ...).
-- We store result of every guarded asserion as a boolean value
-- in TEStack (e.g. `EQ` will store true if it's arguments equal).
-- Each guarded assertion is associated with a single snapshot.
-- So, every snapshot has a set of guarded assertions.
--
-- How to verify guarded assertions are equivalent:
--
-- 1. Traces equivalence means we exited by the same snapshot,
--    which means any of the assertions in this snapshot is true.
-- 2. For equivalent traces what really matters is the first
--    failed assertion, assertions after it may have
--    arbitrary values.
-- 3. So, we end up with an array of Booleans (one boolean per one
--    snapshot) each boolean means `have we exited by this
--    snapshot`. Notice, that for each trace it looks like this:
--    000001xxxxxx. Some prefix of 0-s, 1 and arbitrary values.
-- 4. After that all we should do is compare these 2 values from 2
--    traces with zero, to check whether both traces exited by a
--    guard.
--
--
--
-- Example:
--
-- local function f()
--   local x = 10
--   return x + 2
-- end
--
-- This code with no optimizations will generate
-- ....        SNAP   #0   [ ---- ]
-- 0001 >  int ADDOV  #x4024000000000000  #x4000000000000000
-- 0002    num CONV   0001  num.int
-- ....        SNAP   #1   [ ---- ---- 0002 ]
--
-- After optimizations this ADDOV will be removed and replaced by:
-- ....        SNAP   #0   [ ---- ]
-- ....        SNAP   #1   [ ---- ---- +12  ]
--
-- Let's ignore SNAP 1 since it doesn't have guards in both cases.
--
-- SNAP 0 in the unoptimized case has 1 guard - first instruction.
-- Set of guards for it is { 1 }.
-- TEStack in the unoptimized case will have
-- single value - `true`:
-- `{(10 + 2 <= INT_MAX && 10 + 2 >= INT_MIN)}`
-- Bitvector of guards will look like
-- {bunch of zeros}{not (10 + 2 <= INT_MAX && 10 + 2 >= INT_MIN)}
--
-- Note, that we added bit negation when constructed bitvector!
--
-- SNAP 0 in optimized case has 0 guards, which means bitvector
-- is simply zero vector.
--
-- Now we should find out, whether first `1` occurs on the same
-- place in both bitvectors. Since second bitvector is zero,
-- it means first one should be zero as well.
-- And, `not (10 + 2 <= INT_MAX && 10 + 2 >= INT_MIN)`
-- is always `false`, as expected.
--
local TEStackBV = {}
extended(TEStackBV, StackBase)

function TEStackBV.init_smt(self, name)
    dev_checks('table', 'string')

    self._name = name
    return string.format('(declare-fun %s () (Array Int Bool))', self._name)
end

function TEStackBV.store(self, op_num, data)
    dev_checks('table', 'number', 'string')
    return string.format('(assert (let ((a!1 %s)) (= (select %s %d) a!1)))',
        data, self._name, op_num
    )
end

function TEStackBV.load(self, slot_num)
    dev_checks('table', 'number')

    return ('(select %s %d)'):format(self._name, slot_num)
end

local SnapStack = {}
extended(SnapStack, StackBase)

function SnapStack.init_smt(self, name)
    dev_checks('table', 'string')

    self._name = name
    self._name_trace_exit = name .. '_te'
    -- SMT expression, of type bitvector, each bit means:
    -- Have we exited by associated snapshot.
    self._exited_by_snap = ('(_ bv0 %d)'):format(smt_constants.MAXSNAP)
    self._cur_stack = 1
    return string.format([[
(declare-fun %s () (Array Int (Array Int (MemCell))))
; %d is arbitrary constant for maximum number of trace exits per snapshot
(declare-fun %s () (_ BitVec %d))
]], self._name, smt_constants.MAXSNAP,
    self._name_trace_exit, smt_constants.MAXSNAP)
end

function SnapStack.load(self, slot_num, type)
    dev_checks('table', 'number', 'string')

    local stack = string.format('(select %s %d)', self._name, self._cur_stack)
    local slot = string.format('(select %s %d)', stack, slot_num)
    local conv
    if bv2type[type] == nil then
        return ''
    else
        conv = assert(bv2type[type], 'Unsupported load type ' .. type, nil)
    end
    return string.format(conv, extract_value(slot, op_type.NUM))
end

function SnapStack.load_te(self)
    return string.format('%s', self._name_trace_exit)
end

-- In the end we have a huge boolean formula `_name_trace_exit`,
-- collected during `inc`.
function SnapStack.finalize(self)
    return ('(assert (= %s %s))'):format(
        self._name_trace_exit, self._exited_by_snap
    )
end

function SnapStack.store(self, slot_num, type, data)
    dev_checks('table', 'number', 'string', 'string')

    local conv = assert(type2bv[type], 'Unsupported load op type ' .. type)
    local conv_data = create_value(string.format(conv, data), op_type.NUM)
    local stack = string.format('(select %s %d)', self._name, self._cur_stack)
    local new_stack = string.format('(store %s %d %s)',
        stack, slot_num, conv_data
    )

    return string.format('(assert (= %s %s))', stack, new_stack)
end

-- On each snapshot we will store at pos (1 << _cur_stack)
-- an smt formula, which contains boolean value:
-- `true` if exited by this snapshot.
function SnapStack.inc(self, snap_id, exit_by_this_snap, ctx)
    dev_checks('table', 'number', '?string', 'table')

    if (exit_by_this_snap ~= nil) then
        local id
        local key = self._name .. "_" .. snap_id
        -- Snapshots should be ordered, matching by ID
        -- is not enough.
        -- E.g. A_0 B and A_1 B, if we first
        -- compare B then A it's possible we exited by B,
        -- but A_0 and A_1 are different,
        -- so solver will give SAT.
        if ctx.snap_mapping.map[key] then
            utils.debug_msg("old: " .. key .. ctx.snap_mapping.map[key])
            id = ctx.snap_mapping.map[key]
        else
            utils.debug_msg("new: " .. key .. ctx.snap_mapping.cur_id)
            ctx.snap_mapping.map[key] = ctx.snap_mapping.cur_id
            ctx.snap_mapping.cur_id = ctx.snap_mapping.cur_id + 1
            id = ctx.snap_mapping.map[key]
        end

        local masked = ('(bvshl (_ bv1 %d) (_ bv%d %d))'):format(
            smt_constants.MAXSNAP,
            id,
            smt_constants.MAXSNAP)
        self._exited_by_snap =
            ('(bvor %s\n    (ite (not %s) %s (_ bv0 %d)))'):format(
            self._exited_by_snap,
            exit_by_this_snap,
            masked,
            smt_constants.MAXSNAP
        )
    end
    self._cur_stack = self._cur_stack + 1
end

-- We model memory as 3D array: [versions][pointer][array].
-- When we want to modify array we increase version.
-- All reads happen from the latest version.
local MemoryStack = {}
extended(MemoryStack, StackBase)

-- Idea is that we have:
--          main_stack
--       /             \
--      /               \
--  optimized_stack     unoptimized_stack
-- At 0 version they are equal. On every store we increment
-- version of the slot, preserving old value for all others slots.
-- mem[v+1][key] = (store mem[v] key (store mem[v][key] idx val))
function MemoryStack.init_smt(self, name, base_stack)
    dev_checks('table', 'string', '?table')

    self._name = name
    self.base_stack = base_stack
    self.keys_lookup = {}
    -- Auto-allocated slot ids are strictly negative so they
    -- can be distinguished from VM-slot-derived ids (>= 0) in
    -- the equivalence disjunct's witness guard.
    self.next_free = -1
    -- base_slot -> { slot }
    self.vm_slot_map = {}
    -- [Version][Slot][Data]
    local mutable_memory = string.format(
        '(declare-fun %s () MemPtr)',
        self._name
    )
    self._version = 0
    if base_stack ~= nil then
        mutable_memory = mutable_memory .. '\n' .. (
            '(assert (= (select %s 0) (select %s 0)))'
        ):format(self._name, base_stack._name)
    end
    return mutable_memory
end

function MemoryStack.alloc_slot(self)
    local current_slot = tostring(self.next_free)
    self.next_free = self.next_free - 1
    return current_slot
end

-- Takes as input op num (e.g. 0001) or
-- "string" and returns unique id which will
-- always be associated with this key in all
-- memory operations on this stack.
--
-- Consider it like hash, but without holes.
function MemoryStack.key_id(self, key)
    -- TODO: Add some prefix for types
    -- to maintain correctness at every slot.
    if self.keys_lookup[key] == nil then
        self.keys_lookup[key] = self:alloc_slot()
    end
    return self.keys_lookup[key]
end

function MemoryStack.get_version(self)
    return tostring(self._version)
end

function MemoryStack.inc_version(self)
    self._version = self._version + 1
    return self:get_version()
end

function MemoryStack.allocate(self, inherited_from)
    dev_checks('table', '?number')

    local current_slot
    if inherited_from ~= nil then
        -- Non nil `inherited_from` means this table is non-local
        -- and tied to base stack.
        assert(self.base_stack ~= nil)
        local str_id = tostring(inherited_from)
        -- Idempotent for the same `inherited_from`: a single
        -- VM slot may be SLOAD'd multiple times in one trace
        -- (e.g. globals-normalized FLOAD func.env collapses to
        -- repeated `SLOAD #GLOBALS_SLOT`). Hand back the same
        -- local slot so all uses share one version chain.
        if self.vm_slot_map[str_id] ~= nil then
            return self.vm_slot_map[str_id].slot, ''
        end
        -- Use the VM slot id itself as the local slot id so unopt
        -- and opt stacks agree on the integer that ends up as a
        -- `tab-val` literal. With independent alloc_slot counters
        -- the same VM SLOAD could land at different local ids
        -- across stacks (counter drift from differing IR length
        -- before the SLOAD), and any downstream store that embeds
        -- the slot id into another array makes the memory-diff
        -- disjunct spuriously sat.
        current_slot = str_id
        self.vm_slot_map[str_id] = { slot = current_slot }
        return current_slot, ''
    end
    current_slot = self:alloc_slot()
    local result = ('\n(assert (= (select (select %s 0) %s) zero_pointer))')
        :format(self._name, current_slot)
    return current_slot, result
end

-- Read whole table from ptr at current version.
function MemoryStack.load(self, ptr)
    dev_checks('table', 'string')

    return ('(select (select %s %s) %s)'):format(
        self._name, self:get_version(), ptr
    )
end

-- Read single value from ptr at current version at idx.
function MemoryStack.load_index(self, ptr, idx, type)
    dev_checks('table', 'string', 'string', 'string')

    local memory_array = self:load(ptr)
    local conv = assert(bv2type[type], 'Unsupported load op type ' .. type)
    return conv:format(
        extract_value(('(select %s %s)'):format(memory_array, idx), type)
    )
end

-- Save data to ptr at new version.
function MemoryStack.store(self, ptr, data)
    dev_checks('table', 'string', 'string')

    local old_ver = self:get_version()
    local new_ver = self:inc_version()
    return ('(assert (= (select %s %s) (store (select %s %s) %s %s)))'):format(
        self._name, new_ver, self._name, old_ver, ptr, data
    )
end

-- Save data to ptr at new version.
function MemoryStack.store_index(self, ptr, index, data, type)
    dev_checks('table', 'string', 'string', 'string', 'string')

    local conv = assert(type2bv[type], 'Unsupported load op type ' .. type)
    data = conv:format(data)
    local old_ver = self:get_version()
    local new_ver = self:inc_version()
    local val = ([[(assert (let (
    (old_version (select %s %s))
    (key %s)
    (index %s)
    (data %s)
) (let (
        (updated_inner (store (select old_version key) index data))
) (= (select %s %s) (store old_version key updated_inner)))))]]):format(
        self._name, old_ver, ptr, index,
        create_value(data, type),
        self._name, new_ver
    )
    return val
end

local SMTContext = {}
function SMTContext:new(vm_stack_type, op_stack_type)
    dev_checks('table', 'string', 'string')

    if vm_stack_type == 'BV' then
        self.vm_stack = VMStackBV:new()
    else
        error('Unsupported VMStack type')
    end

    if op_stack_type == 'BV' then
        self.op_stack = OpStackBV:new()
    else
        error('Unsupported OpStack type')
    end

    self.te_stack = TEStackBV:new()
    self.mem_stack = MemoryStack:new()
    self.snap_stack = SnapStack:new()
    self.snap_mapping = { cur_id = 0, map = {} }

    -- ssa_ref -> num constant value (for constant propagation)
    self.const_nums = {}
    -- ssa_ref -> string constant value (for constant propagation)
    self.const_strs = {}
    -- ssa_ref -> Lua-level key string (set by HREFK/HREF)
    self.href_keys = {}
    -- ssa_ref -> { asize, hmask, content = { key -> OpKind } }
    -- Aliased via HREF/HREFK/NEWREF (same Lua table ref).
    self.const_tabs = {}
    -- vm-slot -> same dict as above; reused so two SLOADs of one
    -- stack slot share a const_tabs entry. Otherwise an HSTORE
    -- through the first SLOAD's chain is invisible to a later
    -- HLOAD through the second SLOAD's chain.
    self.const_tabs_by_slot = {}

    return self
end

function SMTContext:restart()
    self.const_nums = {}
    self.const_strs = {}
    self.href_keys = {}
    self.const_tabs = {}
    self.const_tabs_by_slot = {}
end

return {
    create_value = create_value,
    extract_value = extract_value,
    SMTContext = SMTContext,
    MemoryStack = MemoryStack,
}
