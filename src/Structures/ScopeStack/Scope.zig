const std = @import("std");
const Binding = @import("Binding.zig");
const Self = @This();
pub const Error = error{
    AlreadyDeclared,
    UndeclaredVariable,
} || std.mem.Allocator.Error;
variables: std.StringHashMapUnmanaged(Binding),
pub fn init() Self {
    return .{
        .variables = .empty,
    };
}
pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.variables.deinit(allocator);
}

pub fn declare(self: *Self, allocator: std.mem.Allocator, name: []const u8, is_mutable: bool, slot: u16) Error!void {
    const result = try self.variables.getOrPut(allocator, name);
    if (result.found_existing)
        return Error.AlreadyDeclared;
    result.value_ptr.* = Binding{
        .is_mutable = is_mutable,
        .slot = slot,
        .is_initialized = false,
    };
}
pub fn define(self: *Self, name: []const u8) Error!void {
    const v = self.variables.getPtr(name) orelse return Error.UndeclaredVariable;
    v.is_initialized = true;
}
pub fn lookup(self: *Self, name: []const u8) ?Binding {
    return self.variables.get(name);
}
