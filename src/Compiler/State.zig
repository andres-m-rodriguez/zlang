const std = @import("std");
const Bytecode = @import("../Structures/Bytecode.zig");
const Self = @This();

has_return: bool,
slot_types: std.AutoHashMapUnmanaged(u32, Bytecode.PrimKind),
current_return_kind: Bytecode.PrimKind,

pub fn init() Self {
    return .{
        .has_return = false,
        .slot_types = .empty,
        .current_return_kind = .Void,
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.slot_types.deinit(allocator);
}
