--[[
Provides different types of stacks for IR. Data stored in stacks
is used for checking if two IR traces are equivalent.
]]--

local smt_constants = require('ljopt.smt_constants')

local dev_checks = require('ljopt.dev_checks')

local function extended(child, parent)
    dev_checks('table', 'table')

    setmetatable(child, { __index = parent })
end

local type2bv = {
    ['tab'] = '%s',
    ['flt'] = '(fp.to_ieee_bv (bvand %s #x00000000ffffffff))',
    ['i8']  = '(bvand %s #x00000000000000ff)',
    ['u8']  = '(bvand %s #x00000000000000ff)',
    ['i16'] = '(bvand %s #x000000000000ffff)',
    ['u16'] = '(bvand %s #x000000000000ffff)',
    ['u32'] = '(bvand %s #x00000000ffffffff)',
    ['int'] = '(bvand %s #x00000000ffffffff)',
    ['u64'] = '%s',
    ['i64'] = '%s',
    ['num'] = '(fp.to_ieee_bv %s)',
}

local bv2type = {
    ['tab'] = '%s',
    ['flt'] = '((_ to_fp 9 24) (bvand %s #x00000000ffffffff))',
    ['i8']  = '(bvand %s #x00000000000000ff)',
    ['u8']  = '(bvand %s #x00000000000000ff)',
    ['i16'] = '(bvand %s #x000000000000ffff)',
    ['u16'] = '(bvand %s #x000000000000ffff)',
    ['u32'] = '(bvand %s #x00000000ffffffff)',
    ['int'] = '(bvand %s #x00000000ffffffff)',
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

    local conv = assert(bv2type[type], 'Unsupported load op type ' .. type)
    local val = string.format('(select %s %d)', self._name, op_num)
    return string.format(conv, val)
end

function OpStackBV.store(self, op_num, type, data)
    dev_checks('table', 'number', 'string', 'string')

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
-- 4. The simplest way to compare these prefixes is reverse the
--    bitvector, now we're looking for their suffix of the form
--    10000. Let's introduce `lsb` - least significant bit in SMT,
--    which will return 000001000000. We can do it effectively
--    using bitwise trick `x & (-x)`.
-- 5. After that all we should do is compare these 2 values from 2
--    traces.
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
function SnapStack.inc(self, exit_by_this_snap)
    dev_checks('table', '?string')

    if (exit_by_this_snap ~= nil) then
        local masked = ('(bvshl (_ bv1 %d) (_ bv%d %d))'):format(
            smt_constants.MAXSNAP,
            self._cur_stack,
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
    self.snap_stack = SnapStack:new()

    return self
end

return {
    SMTContext = SMTContext
}
