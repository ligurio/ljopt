--[[
    Provides different types of stacks for IR.
    Data stored in stacks is used for checking if
    two IR traces are equivalent.
]]--

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
    return string.format('(declare-fun %s () (Array Int (Array Int (_ BitVec 64))))', name)
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
    local stack = string.format('(select %s %d)', self._name, self._cur_stack)
    local new_stack = string.format('(store %s %d %s)', stack, slot_num, conv_data)
    self.cur_stack = self.cur_stack + 1
    local new_location = string.format('(select %s %d)', self._name, self._cur_stack)
    return string.format('(assert (= %s %s))', new_location, new_stack)
end

local OpStackBV = {}
extended(OpStackBV, StackBase)

function OpStackBV.init_smt(self, name)
    dev_checks('table', 'string')

    self._name = name
    return string.format('(declare-fun %s () (Array Int (_ BitVec 64)))', self._name)
end

function OpStackBV.load(self, op_num, type)
    dev_checks('table', 'number', 'string')

    local conv = assert(bv2type[type], 'Unsupported load op type ' .. type)
    local val = string.format('(select %s %d)', self._name, op_num)
    return string.format(conv, val)
end

function OpStackBV.store(self, op_num, type, data)
    -- dev_checks('table', 'number', 'string', 'string')

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


local TEStackBV = {}
extended(TEStackBV, StackBase)

function TEStackBV.init_smt(self, name)
    dev_checks('table', 'string')

    self._name = name
    return string.format('(declare-fun %s () (Array Int Bool))', self._name)
end

function TEStackBV.store(self, op_num, type, data)
    dev_checks('table', 'number', 'string', 'string')

    assert(true, type)
    return string.format('(assert (let ((a!1 %s)) (= (select %s %d) a!1)))', data, self._name, op_num)
end

local SnapStack = {}
extended(SnapStack, StackBase)

function SnapStack.init_smt(self, name)
    dev_checks('table', 'string')

    self._name = name
    self._cur_stack = 0
    return string.format('(declare-fun %s () (Array Int (Array Int (_ BitVec 64))))', self._name)
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
