const std = @import("std");
const Ast = @import("Structures/Ast.zig");
const Self = @This();
pub const Error = error{
    UndefinedVariable,
};
values: std.StringHashMapUnmanaged(Ast.Value),
pub fn init() Self {
    return .{ .values = .{} };
}
pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.values.deinit(allocator);
}
pub fn define(self: *Self, allocator: std.mem.Allocator, name: []const u8, value: Ast.Value) !void {
    try self.values.put(allocator, name, value);
}

pub fn get(self: *Self, name: []const u8) Error!Ast.Value {
    return self.values.get(name) orelse Error.UndefinedVariable;
}
