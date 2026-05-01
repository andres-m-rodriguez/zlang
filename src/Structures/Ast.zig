const std = @import("std");

pub const Statement = union(enum) {
    let: LetStmt,
    expression: *Expression,

    pub fn createLet(
        allocator: std.mem.Allocator,
        name: []const u8,
        type_annotation: ?[]const u8,
        value: *Expression,
    ) !*Statement {
        const node = try allocator.create(Statement);
        node.* = .{ .let = .{ .name = name, .type_annotation = type_annotation, .value = value } };
        return node;
    }

    pub fn createExpression(allocator: std.mem.Allocator, expr: *Expression) !*Statement {
        const node = try allocator.create(Statement);
        node.* = .{ .expression = expr };
        return node;
    }

    pub fn deinit(self: *Statement, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .let => |l| l.deinit(allocator),
            .expression => |e| e.deinit(allocator),
        }
        allocator.destroy(self);
    }
};

pub const LetStmt = struct {
    name: []const u8,
    type_annotation: ?[]const u8,
    value: *Expression,

    pub fn deinit(self: LetStmt, allocator: std.mem.Allocator) void {
        self.value.deinit(allocator);
    }
};
pub const Value = union(enum) {
    number: f64,
    string: []const u8,
    boolean: bool,
    nil,

    pub fn createNumber(value: []const u8) !Value {
        const parsed = try std.fmt.parseFloat(f64, value);
        return .{ .number = parsed };
    }

    pub fn createString(value: []const u8) Value {
        return .{ .string = value };
    }

    pub fn createBoolean(value: bool) Value {
        return .{ .boolean = value };
    }

    pub fn createNil() Value {
        return .nil;
    }
};
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

pub const BinOp = enum {
    add,
    sub,
    mul,
    div,
};

pub const UnaryOp = enum {
    negate,
};
