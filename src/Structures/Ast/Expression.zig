const std = @import("std");
const Value = @import("Value.zig").Value;
const Op = @import("Op.zig");
const BinOp = Op.BinOp;
const UnaryOp = Op.UnaryOp;

pub const Expression = union(enum) {
    literal: Value,
    binary: BinaryExpr,
    identifier: []const u8,
    unary: UnaryExpr,
    grouping: *Expression,

    pub fn deinit(self: *Expression, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .binary => |b| b.deinit(allocator),
            .unary => |u| u.deinit(allocator),
            .grouping => |g| g.deinit(allocator),
            .literal, .identifier => {},
        }
        allocator.destroy(self);
    }

    pub fn createLiteral(allocator: std.mem.Allocator, value: Value) !*Expression {
        const node = try allocator.create(Expression);
        node.* = .{ .literal = value };
        return node;
    }
    pub fn createBinary(allocator: std.mem.Allocator, op: BinOp, left: *Expression, right: *Expression) !*Expression {
        const node = try allocator.create(Expression);
        node.* = .{ .binary = .{ .op = op, .left = left, .right = right } };
        return node;
    }
    pub fn createIdentifier(allocator: std.mem.Allocator, name: []const u8) !*Expression {
        const node = try allocator.create(Expression);
        node.* = .{ .identifier = name };
        return node;
    }
    pub fn createUnary(allocator: std.mem.Allocator, op: UnaryOp, operand: *Expression) !*Expression {
        const node = try allocator.create(Expression);
        node.* = .{ .unary = .{ .op = op, .operand = operand } };
        return node;
    }

    pub fn createGrouping(allocator: std.mem.Allocator, inner: *Expression) !*Expression {
        const node = try allocator.create(Expression);
        node.* = .{ .grouping = inner };
        return node;
    }
};

pub const BinaryExpr = struct {
    op: BinOp,
    left: *Expression,
    right: *Expression,
    pub fn deinit(self: BinaryExpr, allocator: std.mem.Allocator) void {
        self.left.deinit(allocator);
        self.right.deinit(allocator);
    }
};

pub const UnaryExpr = struct {
    op: UnaryOp,
    operand: *Expression,

    pub fn deinit(self: UnaryExpr, allocator: std.mem.Allocator) void {
        self.operand.deinit(allocator);
    }
};
