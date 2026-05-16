const Bytecode = @import("Bytecode.zig");
const Value = @import("Structures/Ast/Value.zig").Value;
const Self = @This();

chunk: *const Bytecode,
pc: usize,
locals: []Value,

