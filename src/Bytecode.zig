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
    OP_CALL,
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
pub fn init() Self {
    return .{ .code = &.{}, .constants = &.{} };
}
pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.free(self.code);
    allocator.free(self.constants);
}
pub fn readOpcode(self: *const Self, pc: usize) Opcode {
    const byte = self.code[pc];
    const max_tag = @intFromEnum(Opcode.Return);
    if (byte > max_tag) {
        std.debug.print(
            "readOpcode failed at pc={d}: byte=0x{x:0>2} ({d}), max_valid={d}, code.len={d}\n",
            .{ pc, byte, byte, max_tag, self.code.len },
        );
        const start = if (pc >= 4) pc - 4 else 0;
        const end = @min(pc + 5, self.code.len);
        std.debug.print("  context bytes [{d}..{d}]:", .{ start, end });
        for (self.code[start..end], start..) |b, i| {
            const marker: []const u8 = if (i == pc) " >" else " ";
            std.debug.print("{s}0x{x:0>2}", .{ marker, b });
        }
        std.debug.print("\n", .{});
        @panic("invalid opcode");
    }
    return @enumFromInt(byte);
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
        .OP_CALL => 5, // u32 + u8 (fn_indx and number of args)
        else => 0,
    };
}
