const std = @import("std");
const Value = @import("Ast/Value.zig").Value;
const Self = @This();

pub const PrimKind = enum {
    F64,
    Bool,
    Void,
};

pub fn primSize(kind: PrimKind) u32 {
    return switch (kind) {
        .F64 => 8,
        .Bool => 1,
        .Void => 0,
    };
}

pub const Opcode = enum(u8) {
    // Constants & literals
    LoadConst,      // operand: u8 const_idx — constant is f64, pushes 8 bytes
    LoadTrue,       // pushes 1 byte
    LoadFalse,      // pushes 1 byte

    // Locals (typed)
    LoadLocalF64,   // operand: u32 slot
    LoadLocalBool,
    StoreLocalF64,
    StoreLocalBool,

    // Calls
    OP_CALL,        // operand: u32 fn_idx — arg widths come from Program.Function.param_kinds

    // Arithmetic (f64, f64 → f64)
    Add,
    Sub,
    Mul,
    Div,

    // Comparison (f64, f64 → bool)
    Lt,
    Lte,
    Gt,
    Gte,

    // Equality (typed)
    EqF64,
    EqBool,
    NeqF64,
    NeqBool,

    // Unary
    Neg,            // f64 → f64
    Not,            // bool → bool

    // Control flow
    Jump,
    JumpIfFalse,
    Loop,

    // Termination (typed)
    ReturnF64,
    ReturnBool,
    ReturnVoid,
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
    const max_tag = @intFromEnum(Opcode.ReturnVoid);
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
        .LoadLocalF64, .LoadLocalBool, .StoreLocalF64, .StoreLocalBool => 4,
        .Jump, .JumpIfFalse, .Loop => 2,
        .OP_CALL => 4,
        else => 0,
    };
}
