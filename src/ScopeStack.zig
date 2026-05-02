const std = @import("std");
const Environment = @import("Environment.zig");
const Ast = @import("Structures/Ast.zig");

const Self = @This();

pub const Error = error{
    UndefinedVariable,
    OutOfMemory,
};

scopes: std.ArrayList(Environment),

pub const empty: Self = .{ .scopes = .empty };

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    for (self.scopes.items) |*env| env.deinit(allocator);
    self.scopes.deinit(allocator);
}

pub fn push(self: *Self, allocator: std.mem.Allocator) Error!void {
    try self.scopes.append(allocator, Environment.init());
}

pub fn pop(self: *Self, allocator: std.mem.Allocator) void {
    if (self.scopes.items.len == 0) return;
    var env = self.scopes.pop() orelse return;
    env.deinit(allocator);
}

pub fn define(self: *Self, allocator: std.mem.Allocator, name: []const u8, value: Ast.Value) Error!void {
    if (self.scopes.items.len == 0) {
        try self.scopes.append(allocator, Environment.init());
    }
    const top = &self.scopes.items[self.scopes.items.len - 1];
    try top.define(allocator, name, value);
}

pub fn get(self: *Self, name: []const u8) Error!Ast.Value {
    var i = self.scopes.items.len;
    while (i > 0) {
        i -= 1;
        if (self.scopes.items[i].values.get(name)) |v| return v;
    }
    return error.UndefinedVariable;
}

pub fn assign(self: *Self, allocator: std.mem.Allocator, name: []const u8, value: Ast.Value) Error!void {
    var i = self.scopes.items.len;
    while (i > 0) {
        i -= 1;
        if (self.scopes.items[i].values.contains(name)) {
            try self.scopes.items[i].values.put(allocator, name, value);
            return;
        }
    }
    return error.UndefinedVariable;
}
