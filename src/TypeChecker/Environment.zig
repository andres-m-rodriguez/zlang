const std = @import("std");
const ZType = @import("../Structures/Ast/ZType.zig");
const Self = @This();

const Scope = std.StringHashMapUnmanaged(ZType.Kind);
scopes: std.ArrayList(Scope),

pub fn init() Self {
    return .{ .scopes = .empty };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    for (self.scopes.items) |*scope| scope.deinit(allocator);
    self.scopes.deinit(allocator);
}

pub fn beginScope(self: *Self, allocator: std.mem.Allocator) !void {
    try self.scopes.append(allocator, .empty);
}

pub fn endScope(self: *Self, allocator: std.mem.Allocator) void {
    var popped = self.scopes.pop().?;
    popped.deinit(allocator);
}

pub fn declare(self: *Self, allocator: std.mem.Allocator, name: []const u8, kind: ZType.Kind) !void {
    const current = &self.scopes.items[self.scopes.items.len - 1];
    try current.put(allocator, name, kind);
}

pub fn lookup(self: *const Self, name: []const u8) ?ZType.Kind {
    var i = self.scopes.items.len;
    while (i > 0) {
        i -= 1;
        if (self.scopes.items[i].get(name)) |kind| return kind;
    }
    return null;
}
