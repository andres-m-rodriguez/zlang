const std = @import("std");
const Value = @import("Ast.zig").Value;
const ValueContext = @import("Ast.zig").ValueContext;

const Self = @This();

pub const Error = error{
    TooManyConstants,
} || std.mem.Allocator.Error;

constants: std.ArrayList(Value),
indices: std.HashMapUnmanaged(Value, u8, ValueContext, 80),

pub fn init() Self {
    return .{
        .constants = .empty,
        .indices = .empty,
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.constants.deinit(allocator);
    self.indices.deinit(allocator);
}

pub fn add(self: *Self, allocator: std.mem.Allocator, value: Value) Error!u8 {
    const result = try self.indices.getOrPut(allocator, value);
    if (result.found_existing) {
        return result.value_ptr.*;
    }
    if (self.constants.items.len >= std.math.maxInt(u8)) {
        return Error.TooManyConstants;
    }
    const idx: u8 = @intCast(self.constants.items.len);
    try self.constants.append(allocator, value);
    result.value_ptr.* = idx;
    return idx;
}

pub fn get(self: *const Self, idx: u8) Value {
    return self.constants.items[idx];
}

pub fn toOwnedSlice(self: *Self, allocator: std.mem.Allocator) ![]Value {
    self.indices.clearAndFree(allocator);
    return self.constants.toOwnedSlice(allocator);
}
