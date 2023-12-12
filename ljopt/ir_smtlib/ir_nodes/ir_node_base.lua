ir_node_base = {}
function ir_node_base:new(ssa_ref, flags, type, opcode, left_op, right_op)
    local public = {}
        public.ssa_ref = ssa_ref
        public.flags = flags
        public.type = type
        public.opcode = opcode
        public.left_op = left_op
        public.right_op = right_op

        -- TODO: Prevent this methods from overriding in derived classes.
        function public:get_ssa_reference()
            return self.ssa_ref
        end

        function public:get_flags()
            return self.flags
        end

        function public:get_type()
            return self.type
        end

        function public:get_opcode()
            return self.opcode
        end

        function public:get_left_op()
            return self.left_op
        end

        function public:get_right_op()
            return self.right_op
        end

        function public:parse_op(operand, maxrecord)
            -- TODO support for other types
            maxrecord = maxrecord or 4000
            -- TODO inf?
            -- TODO other modifiers
            if operand:sub(1, 1) == '+' or operand:sub(1, 1) == '-' or
               operand:sub(-1, -1) == 'L' or operand == "NaN" then
                -- TODO support for arith other types
                assert(self:get_type() == "num" or self:get_type() == "int" or
                       self:get_type() == "i64" or self:get_type() == "u64")
                return self:get_type()
            elseif string.len(operand) == string.len(tostring(maxrecord)) then
                return "op"
            end
        end

        function public:retrieve_slot_op(operand)
            return tonumber(operand:sub(2))
        end

        function public:retrieve_num_op(operand, ctx)
            local op_type = self:parse_op(operand)
            if op_type == "op" then
                operand = ctx.op_stack:load(tonumber(operand), self:get_type())
            elseif op_type == "num" then
                -- TODO rewrite
                local conv = "((_ to_fp 11 53) roundNearestTiesToEven %s)"
                operand = operand:gsub("e", " "):gsub("+", "")
                operand = string.format(conv, operand)
            end
            return operand
        end

        function public:retrieve_int_op(operand, ctx)
            local op_type = self:parse_op(operand)
            if op_type == "op" then
                operand = ctx.op_stack:load(tonumber(operand), self:get_type())
            elseif op_type == "int" then
                local conv = string.format("#x%.16x", operand)
                operand = string.format(conv, operand)
            end
            return operand
        end

        function public:retrieve_i64_op(operand, ctx)
            local op_type = self:parse_op(operand)
            if op_type == "op" then
                operand = ctx.op_stack:load(tonumber(operand), self:get_type())
            elseif op_type == "i64" then
                local conv = string.format("#x%.32x", operand)
                operand = string.format(conv, operand)
            end
            return operand
        end

        function to_smt_lib()
            return assert(false, "Unimplemented", nil)
        end

    setmetatable(public, self)
    self.__index = self;
    return public
end

function extended(child, parent)
    setmetatable(child, { __index = parent })
end

return {
    ir_node_base = ir_node_base,
    extended = extended
}
