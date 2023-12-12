local type2bv = {
    ["tab"] = "%s",
    ["flt"] = "(fp.to_ieee_bv (bvand %s #x00000000ffffffff))",
    ["i8"]  = "(bvand %s #x00000000000000ff)",
    ["u8"]  = "(bvand %s #x00000000000000ff)",
    ["i16"] = "(bvand %s #x000000000000ffff)",
    ["u16"] = "(bvand %s #x000000000000ffff)",
    ["u32"] = "(bvand %s #x00000000ffffffff)",
    ["int"] = "(bvand %s #x00000000ffffffff)",
    ["u64"] = "%s",
    ["i64"] = "%s",
    ["num"] = "(fp.to_ieee_bv %s)",
}

local bv2type = {
    ["tab"] = "%s",
    ["flt"] = "((_ to_fp 9 24) (bvand %s #x00000000ffffffff))",
    ["i8"]  = "(bvand %s #x00000000000000ff)",
    ["u8"]  = "(bvand %s #x00000000000000ff)",
    ["i16"] = "(bvand %s #x000000000000ffff)",
    ["u16"] = "(bvand %s #x000000000000ffff)",
    ["u32"] = "(bvand %s #x00000000ffffffff)",
    ["int"] = "(bvand %s #x00000000ffffffff)",
    ["u64"] = "%s",
    ["i64"] = "%s",
    ["num"] = "((_ to_fp 11 53) %s)",
}

local Vm_stack = {}
function Vm_stack:new()
    local public = {}

    function Vm_stack:init_smt(name)
    end

    function Vm_stack:load(slot_num, type)
    end

    function Vm_stack:store(slot_num, type, data)
    end

    setmetatable(public, self)
    self.__index = self;
    return public
end

local Vm_stack_bv = {}
setmetatable(Vm_stack_bv, { __index = Vm_stack })

function Vm_stack_bv:init_smt(name)
    self.name = name
    self.cur_stack = 0
    return string.format("(declare-fun %s () (Array Int (Array Int (_ BitVec 64))))", name)
end

function Vm_stack_bv:load(slot_num, type)
    local stack = string.format("(select %s %d)", self.name, self.cur_stack)
    local slot = string.format("(select %s %d)", stack, slot_num)
    local conv = ''
    if bv2type[type] == nil then
        return ''
    else
        conv = assert(bv2type[type], "Unsupported load type " .. type, nil)
    end
    return string.format(conv, slot)
end

function Vm_stack_bv:store(slot_num, type, data)
    local conv = assert(type2bv[type], "Unsupported load op type " .. type, nil)
    local conv_data = string.format(conv, data)
    local stack = string.format("(select %s %d)", self.name, self.cur_stack)
    local new_stack = string.format("(store %s %d %s)", stack, slot_num, conv_data)
    self.cur_stack = self.cur_stack + 1
    local new_location = string.format("(select %s %d)", self.name, self.cur_stack)
    return string.format("(assert (= %s %s))", new_location, new_stack)
end

-- TODO datatype-based vm_stack
local Vm_stack_dt = {}
setmetatable(Vm_stack_dt, { __index = Vm_stack })


local Op_stack = {}
function Op_stack:new()
    local public = {}

    function Op_stack:init_smt(name)
    end

    function Op_stack:load(op_num, type)
    end

    function Op_stack:store(op_num, type, data)
    end

    setmetatable(public, self)
    self.__index = self;
    return public
end

local Op_stack_bv = {}
setmetatable(Op_stack_bv, { __index = Op_stack })

function Op_stack_bv:init_smt(name)
    self.name = name
    return string.format("(declare-fun %s () (Array Int (_ BitVec 64)))", name)
end

function Op_stack_bv:load(op_num, type)
    local conv = assert(bv2type[type], "Unsupported load op type " .. type, nil)
    local val = string.format("(select %s %d)", self.name, op_num)
    return string.format(conv, val)
end

function Op_stack_bv:store(op_num, type, data)
    if data == '' then
        return ''
    end
    local conv = assert(type2bv[type], "Unsupported store op type " .. type, nil)
    return string.format("(assert (let ((a!1 %s)) (= (select %s %d) a!1)))", string.format(conv, data), self.name, op_num)
end

-- TODO datatype-based op_stack
local Op_stack_dt = {}
setmetatable(Op_stack_dt, { __index = Op_stack })


local Te_stack = {}
function Te_stack:new()
    local public = {}

    function Te_stack:init_smt(name)
        self.name = name
        return string.format("(declare-fun %s () (Array Int Bool))", name)
    end

    function Te_stack:load(op_num, type)
        assert(false)
    end

    function Te_stack:store(op_num, type, data)
        return string.format("(assert (let ((a!1 %s)) (= (select %s %d) a!1)))", data, self.name, op_num)
    end

    setmetatable(public, self)
    self.__index = self;
    return public
end

local Te_stack_bv = {}
setmetatable(Te_stack_bv, { __index = Te_stack })

function Te_stack_bv:init_smt(name)
    self.name = name
    return string.format("(declare-fun %s () (Array Int Bool))", name)
end

function Te_stack:store(op_num, data)
    -- TODO
end

local Ctx = {}
function Ctx:new(vm_stack_type, op_stack_type)
    local public = {}
    if vm_stack_type == "BV" then
        public.vm_stack = Vm_stack_bv:new()
    else
        error("Unsupported vm_stack type")
    end
    if op_stack_type == "BV" then
        public.op_stack = Op_stack_bv:new()
    else
        error("Unsupported op_stack type")
    end
    public.te_stack = Te_stack:new()

    setmetatable(public, self)
    self.__index = self
    return public
end

local snap_stack = {}
function snap_stack:new()
    local public = {}

    function snap_stack:init_smt(name)
        self.name = name
        self.cur_stack = 0
        return string.format("(declare-fun %s () (Array Int (Array Int (_ BitVec 64))))", name)
    end

    function snap_stack:load(slot_num, type)
    end

    function snap_stack:store(slot_num, type, data)
    end

    setmetatable(public, self)
    self.__index = self;
    return public
end

return Ctx
