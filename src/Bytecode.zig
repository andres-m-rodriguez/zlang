const std = @import("std");
const Value = @import("Structures/Ast/Value.zig").Value;

const Self = @This();

pub const Opcode = enum(u8) {
    // Stack / constants
    LoadConst, 
    LoadTrue,
    LoadFalse,
    LoadLocal, 
    StoreLocal, 
    Pop,
    // Arithmetic
    Add,
    Sub,
    Mul,
    Div,
    // Comparison
    Lt,
    Lte,
    Gt,
    Gte,
    Eq,
    Neq,
    // Unary
    Neg,
    Not,
    // Control flow
    Jump, // operand: u16 forward relative offset
    JumpIfFalse, // operand: u16 forward relative offset; pops a bool
    Loop, // operand: u16 backward relative offset
    // Termination
    Return,
};
code: []const u8,
constants: []const Value,

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.free(self.code);
    allocator.free(self.constants);
}

pub fn readOpcode(self: *const Self, pc: u32) Opcode {
    return @enumFromInt(self.code[pc]);
}

pub fn readU8(self: *const Self, pc: u32) u8 {
    return self.code[pc];
}

pub fn readU16(self: *const Self, pc: u32) u16 {
    return @as(u16, self.code[pc]) | (@as(u16, self.code[pc + 1]) << 8);
}

pub fn getConst(self: *const Self, idx: u8) Value {
    return self.constants[idx];
}

pub fn operandSize(op: Opcode) u32 {
    return switch (op) {
        .LoadConst => 1,
        .LoadLocal, .StoreLocal, .Jump, .JumpIfFalse => 2,
        else => 0,
    };
}
