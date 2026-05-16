const std = @import("std");
const Bytecode = @import("Bytecode.zig");

pub fn dumpBytecode(label: []const u8, bc: *const Bytecode) void {
    std.debug.print("=== {s} ===\n", .{label});
    std.debug.print("-- constants --\n", .{});
    for (bc.constants, 0..) |value, i| {
        std.debug.print("  [{d}] {any}\n", .{ i, value });
    }
    std.debug.print("-- code --\n", .{});
    var pc: u32 = 0;
    while (pc < bc.code.len) {
        const op = bc.readOpcode(pc);
        std.debug.print("  {x:0>4}  {s}", .{ pc, @tagName(op) });
        const size = Bytecode.operandSize(op);
        switch (size) {
            0 => {},
            1 => std.debug.print(" {d}", .{bc.readByte(pc + 1)}),
            2 => std.debug.print(" {d}", .{bc.readU16(pc + 1)}),
            4 => std.debug.print(" {d}", .{bc.readU32(pc + 1)}),
            else => unreachable,
        }
        std.debug.print("\n", .{});
        pc += 1 + size;
    }
}
