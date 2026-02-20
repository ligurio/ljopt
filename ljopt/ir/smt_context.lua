--[[
Provides different types of stacks for IR. Data stored in stacks
is used for checking if two IR traces are equivalent.
]]--

local utils = require('ljopt.utils')
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
    ['num'] = '(fp.to_ieee_bv %s)',
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
    ['num'] = '((_ to_fp 11 53) %s)',
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

local VMStackBV = {}
extended(VMStackBV, StackBase)

function VMStackBV.init_smt(self, name)
    dev_checks('table', 'string')

    self._name = name
    self._cur_stack = 0
    return string.format(
        '(declare-fun %s () (Array Int (Array Int (_ BitVec 64))))', name
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
    return string.format(conv, slot)
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
        '(declare-fun %s () (Array Int (_ BitVec 64)))', self._name
    )
end

function OpStackBV.load(self, op_num, type)
    dev_checks('table', 'number', 'string')

    assert(op_num >= 0,
        'Index is negative, something weird happening: ' .. op_num
    )
    local conv = assert(bv2type[type], 'Unsupported load op type ' .. type)
    local val = string.format('(select %s %d)', self._name, op_num)
    return string.format(conv, val)
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
        string.format(conv, data),
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
(declare-fun %s () (Array Int (Array Int (_ BitVec 64))))
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
    return string.format(conv, slot)
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
    local conv_data = string.format(conv, data)
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

-- Similar to regular programming languages array.
local Array1D = {}
extended(Array1D, StackBase)
function Array1D.init_smt(self, name)
    dev_checks('table', 'string')

    self._name = name
    self._version = 0
    local mutable_memory = string.format(
        '(declare-fun %s () (Array Int (Array Int Int)))', self._name
    )
    -- Our only usecase is versions, we better start
    -- versions from zero.
    -- Apart from that zero-initializing makes this
    -- array comparable in smt.
    local zero_init = ('\n(assert (= (select %s 0) zero_pointer_i_1d))'):format(
        self._name
    )
    return mutable_memory .. '\n' .. zero_init
end

-- Read data from op_num at current version.
function Array1D.load(self, op_num)
    dev_checks('table', 'number')

    local val = string.format('(select %s %d)', self._name, self._version)
    val = string.format('(select %s %s)', val, op_num)
    return val
end

-- Save data to op_num at new version.
-- All consequent reads will read new data.
function Array1D.store(self, op_num, data)
    dev_checks('table', 'number', 'string')

    local prev_version = self._version
    self._version = self._version + 1

    local prev_stack = ('(select %s %d)'):format(self._name, prev_version)
    local updated_stack = ('(store %s %s %s)'):format(prev_stack, op_num, data)

    local new_stack = ('(select %s %d)'):format(self._name, self._version)

    return ('(assert (= %s %s))'):format(new_stack, updated_stack)
end

-- We model memory as 3D array: [pointer][version][array].
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
function MemoryStack.init_smt(self, name, base_stack)
    dev_checks('table', 'string', '?table')

    self._name = name
    self.base_stack = base_stack
    self.keys_lookup = {}
    self.next_free = 0
    -- base_slot -> { slot }
    self.vm_slot_map = {}
    -- [Slot][Version][Data]
    local mutable_memory = string.format(
        '(declare-fun %s () (Array Int (Array Int (Array Int (_ BitVec 64)))))',
        self._name
    )
    self.versions_table = Array1D:new()
    local ver_init = self.versions_table:init_smt('mem_ver_' .. name)
    return mutable_memory .. '\n' .. ver_init
end

function MemoryStack.alloc_slot(self)
    local current_slot = self.next_free
    self.next_free = self.next_free + 1
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

function MemoryStack.slot_version(self, slot)
    return self.versions_table:load(slot)
end

function MemoryStack.inc_version(self, slot)
    return self.versions_table:store(slot, ('(+ %s 1)'):format(
        self.versions_table:load(slot))
    )
end

function MemoryStack.allocate(self, inherited_from)
    dev_checks('table', '?number')

    local result
    local current_slot = self:alloc_slot()
    if inherited_from ~= nil then
        -- Non nil `id` means that allocated
        -- memory should be equal to memory in base stack
        -- (kinda process memory state when trace begins).
        assert(self.base_stack ~= nil)
        result = ('(assert (= %s %s))'):format(
            self.base_stack:load(inherited_from), self:load(current_slot)
        )
        self.vm_slot_map[inherited_from] = { slot = current_slot }
    else
        -- We should assign something to all values by default
        -- to be able to compare them at the end
        -- because we don't track used indexes.
        result = ('\n(assert (= (select (select %s %d) 0) zero_pointer))'):
            format(self._name, current_slot)
    end
    return current_slot, result
end

-- Read whole table from ptr at current version.
function MemoryStack.load(self, ptr)
    dev_checks('table', 'number')

    local val = ([[(let (
    (ptr %s)
    (version %s)
) (select (select %s ptr) version))]]):format(
        ptr, self:slot_version(ptr), self._name
    )
    return val
end

-- Read single value from ptr at current version at idx.
function MemoryStack.load_index(self, ptr, idx)
    dev_checks('table', 'number', 'string')
    local memory_array = self:load(ptr)
    return ('(select %s %s)'):format(memory_array, idx)
end

-- Save data to ptr at new version.
-- All consequent reads will read new data.
function MemoryStack.store(self, ptr, data)
    dev_checks('table', 'number', 'string')

    local inc_ver = self:inc_version(ptr)

    local val = string.format('(select %s %s)', self._name, ptr)
    local new_stack = string.format('(select %s %s)',
        val, self:slot_version(ptr)
    )
    return string.format('%s\n(assert (= %s %s))', inc_ver, new_stack, data)
end

-- Save data to ptr at new version.
-- All consequent reads will read new data.
function MemoryStack.store_index(self, ptr, index, data)
    dev_checks('table', 'number', 'string', 'string')

    local old_version = self:slot_version(ptr)
    local inc_ver = self:inc_version(ptr)
    local new_version = self:slot_version(ptr)
    local val = ([[(assert (let (
    (old_version %s)
    (new_version %s)
    (index %s)
    (data %s)
    (version_array (select %s %s))
) (let (
        (updated_array (store (select version_array old_version) index data))
        (new_array (select version_array new_version))
) (= new_array updated_array))))]]):format(
        old_version, new_version, index, data, self._name, ptr
    )
    return string.format('%s\n%s', inc_ver, val)
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

    -- ssa_ref -> tab_id
    self.tab_info = {}

    return self
end

function SMTContext:restart()
    self.tab_info = {}
end

return {
    SMTContext = SMTContext,
    Array1D = Array1D,
    MemoryStack = MemoryStack,
}
