const std = @import("std");
const Scope = @import("Scope.zig");
const SlotStore = @import("SlotStore.zig");
const Binding = @import("Binding.zig");
const Self = @This();

const ResolveResult = struct {
    binding: Binding,
    depth: usize,
};
pub const Error = error{} || Scope.Error;
scopes: std.ArrayList(Scope),
slots: SlotStore,
pub fn init() Self {
    return .{
        .slots = .init(),
        .scopes = .empty,
    };
}
pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    for (self.scopes.items) |*scope| {
        scope.deinit(allocator);
    }
    self.scopes.deinit(allocator);
}
pub fn beginScope(self: *Self, allocator: std.mem.Allocator) !void {
    const scope = Scope{ .variables = .empty };
    return self.scopes.append(allocator, scope);
}
pub fn endScope(self: *Self, allocator: std.mem.Allocator) void {
    var popped = self.scopes.pop() orelse unreachable; // idk why it returns nullable
    self.slots.release(@intCast(popped.variables.count()));
    popped.deinit(allocator);
}

pub fn declare(self: *Self, allocator: std.mem.Allocator, name: []const u8, is_mutable: bool) !u16 {
    const slot = self.slots.allocate();
    const current_scope = self.getCurrentScope();
    try current_scope.declare(allocator, name, is_mutable, slot);
    return slot;
}
pub fn getCurrentScope(self: *Self) *Scope {
    const current_scope_idx = self.scopes.items.len - 1;
    return &self.scopes.items[current_scope_idx];
}

pub fn define(self: *Self, name: []const u8) !void {
    const current_scope = self.getCurrentScope();
    try current_scope.define(name);
}
pub fn beginFnFrame(self: *Self) SlotStore {
    const saved = self.slots;
    self.slots = SlotStore.init();
    return saved;
}

pub fn endFnFrame(self: *Self, saved: SlotStore) void {
    self.slots = saved;
}

pub fn resolve(self: *Self, name: []const u8) ?ResolveResult {
    var it = std.mem.reverseIterator(self.scopes.items);
    var depth: usize = 0;
    while (it.next()) |s| : (depth += 1) {
        var scope: Scope = s; //LSP doesn't have context of type currently
        if (scope.lookup(name)) |b| return .{ .binding = b, .depth = depth };
    }

    return null;
}
