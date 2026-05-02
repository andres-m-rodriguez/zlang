const std = @import("std");
const Expression = @import("Expression.zig").Expression;

pub const Statement = union(enum) {
    let: LetStmt,
    assign: AssignStmt,
    if_stmt: IfStmt,
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

    pub fn createAssign(
        allocator: std.mem.Allocator,
        name: []const u8,
        value: *Expression,
    ) !*Statement {
        const node = try allocator.create(Statement);
        node.* = .{ .assign = .{ .name = name, .value = value } };
        return node;
    }

    pub fn createIf(
        allocator: std.mem.Allocator,
        condition: *Expression,
        then_branch: []*Statement,
        else_branch: ?[]*Statement,
    ) !*Statement {
        const node = try allocator.create(Statement);
        node.* = .{ .if_stmt = .{
            .condition = condition,
            .then_branch = then_branch,
            .else_branch = else_branch,
        } };
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
            .if_stmt => |i| i.deinit(allocator),
            .assign => |a| a.deinit(allocator),
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
pub const AssignStmt = struct {
    name: []const u8,
    value: *Expression,

    pub fn deinit(self: AssignStmt, allocator: std.mem.Allocator) void {
        self.value.deinit(allocator);
    }
};

pub const IfStmt = struct {
    condition: *Expression,
    then_branch: []*Statement,
    else_branch: ?[]*Statement,

    pub fn deinit(self: IfStmt, allocator: std.mem.Allocator) void {
        self.condition.deinit(allocator);

        for (self.then_branch) |s| s.deinit(allocator);
        allocator.free(self.then_branch);

        if (self.else_branch) |branch| {
            for (branch) |s| s.deinit(allocator);
            allocator.free(branch);
        }
    }
};
