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

pub fn readOpcode(self: *const Self, pc: usize) Opcode {
    return @enumFromInt(self.code[pc]);
}

pub fn readByte(self: *const Self, pc: usize) u8 {
    return self.code[pc];
}

pub fn readU16(self: *const Self, pc: usize) u16 {
    return std.mem.readInt(u16, self.code[pc..][0..2], .little);
}

pub fn readU32(self: *const Self, pc: usize) u32 {
    return std.mem.readInt(u32, self.code[pc..][0..4], .little);
}
pub fn getConst(self: *const Self, idx: u8) Value {
    return self.constants[idx];
}

pub fn operandSize(op: Opcode) u32 {
    return switch (op) {
        .LoadConst => 1,
        .LoadLocal, .StoreLocal => 4, // u32 slot
        .Jump, .JumpIfFalse, .Loop => 2, // u16 offset
        else => 0,
    };
}

