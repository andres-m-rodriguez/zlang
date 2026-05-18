const std = @import("std");
const Value = @import("../Structures/Ast.zig").Value;
const Bytecode = @import("../Structures/Bytecode.zig");
const Self = @This();

pub const Error = error{
    CallStackOverflow,
    LocalsPoolOverflow,
};

pub const Frame = struct {
    chunk: *const Bytecode,
    pc: usize,
    locals: []Value,
};

frames: []Frame,
count: usize,
locals_pool: []Value,
locals_top: usize,

pub fn init(
    allocator: std.mem.Allocator,
    max_frames: usize,
    locals_pool_size: usize,
) !Self {
    return .{
        .frames = try allocator.alloc(Frame, max_frames),
        .count = 0,
        .locals_pool = try allocator.alloc(Value, locals_pool_size),
        .locals_top = 0,
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.free(self.frames);
    allocator.free(self.locals_pool);
}

pub fn push(self: *Self, chunk: *const Bytecode, locals_count: u16) Error!void {
    if (self.count >= self.frames.len) return Error.CallStackOverflow;
    if (self.locals_top + locals_count > self.locals_pool.len) return Error.LocalsPoolOverflow;
    const locals = self.locals_pool[self.locals_top .. self.locals_top + locals_count];
    self.locals_top += locals_count;
    self.frames[self.count] = .{
        .chunk = chunk,
        .pc = 0,
        .locals = locals,
    };
    self.count += 1;
}

pub fn pop(self: *Self) void {
    self.count -= 1;
    self.locals_top -= self.frames[self.count].locals.len;
}

pub fn current(self: *Self) *Frame {
    return &self.frames[self.count - 1];
}

pub fn isEmpty(self: *const Self) bool {
    return self.count == 0;
}
