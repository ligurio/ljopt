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