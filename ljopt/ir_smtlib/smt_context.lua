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
setmetatable(Vm_stack_bv, {__index = Vm_stack})

function Vm_stack_bv:init_smt(name)
    self.name = name
    return string.format("(declare-fun %s () (Array Int (_ BitVec 64)))", name)
end

function Vm_stack_bv:load(slot_num, type)
    -- TODO
end

function Vm_stack_bv:store(slot_num, type, data)
    -- TODO
end


-- TODO datatype-based vm_stack
local Vm_stack_dt = {}
setmetatable(Vm_stack_dt, {__index = Vm_stack})


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
setmetatable(Op_stack_bv, {__index = Op_stack})

function Op_stack_bv:init_smt(name)
    self.name = name
    self.type2bv = {
        ["u64"] = "%s",
        ["i64"] = "%s",
        ["num"] = "(fp.to_ieee_bv %s)",
    }
    self.bv2type = {
        ["u64"] = "%s",
        ["i64"] = "%s",
        ["num"] = "((_ to_fp 11 53) (select %s %d)))",
    }
    return string.format("(declare-fun %s () (Array Int (_ BitVec 64)))", name)
end

function Op_stack_bv:load(op_num, type)
    local conv = assert(self.bv2type[type], "Unsupported load op type "..type, nil)
    return string.format(conv, self.name, op_num)
end

function Op_stack_bv:store(op_num, type, data)
    local conv = assert(self.type2bv[type], "Unsupported store op type "..type, nil)
    return string.format("(assert (= (select %s %d) %s))", self.name, op_num, string.format(conv, data))
end


-- TODO datatype-based op_stack
local Op_stack_dt = {}
setmetatable(Op_stack_dt, {__index = Op_stack})


local Te_stack = {}
function Te_stack:new()
    local public = {}

    function Te_stack:init_smt(name)
        self.name = name
        return string.format("(declare-fun %s () (Array Int Bool))", name)
    end

    function Te_stack:store(op_num, data)
    end

    setmetatable(public, self)
    self.__index = self;
    return public
end


local Te_stack_bv = {}
setmetatable(Te_stack_bv, {__index = Te_stack})

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


return Ctx
