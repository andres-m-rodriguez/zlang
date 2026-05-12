const std = @import("std");
const Expression = @import("Expression.zig").Expression;

pub const Block = struct {
    statements: []*Statement,

    pub fn deinit(self: Block, allocator: std.mem.Allocator) void {
        for (self.statements) |s| s.deinit(allocator);
        allocator.free(self.statements);
    }
};

pub const Statement = union(enum) {
    var_dclr: VarDeclr,
    assign_stmt: AssignStmt,
    if_stmt: IfStmt,
    while_stmt: WhileStmt,
    return_stmt: ReturnStmt,
    expression_stmt: *Expression,

    pub fn createVar(
        allocator: std.mem.Allocator,
        name: []const u8,
        type_annotation: ?[]const u8,
        value: *Expression,
    ) !*Statement {
        const node = try allocator.create(Statement);
        node.* = .{ .var_dclr = .{
            .name = name,
            .type_annotation = type_annotation,
            .is_mutable = true,
            .value = value,
        } };

        return node;
    }
    pub fn createConst(
        allocator: std.mem.Allocator,
        name: []const u8,
        type_annotation: ?[]const u8,
        value: *Expression,
    ) !*Statement {
        const node = try allocator.create(Statement);
        node.* = .{ .var_dclr = .{
            .name = name,
            .type_annotation = type_annotation,
            .is_mutable = false,
            .value = value,
        } };

        return node;
    }

    pub fn createAssign(
        allocator: std.mem.Allocator,
        name: []const u8,
        value: *Expression,
    ) !*Statement {
        const node = try allocator.create(Statement);
        node.* = .{ .assign_stmt = .{ .name = name, .value = value } };
        return node;
    }

    pub fn createIf(
        allocator: std.mem.Allocator,
        condition: *Expression,
        then_branch: Block,
        else_branch: ?Block,
    ) !*Statement {
        const node = try allocator.create(Statement);
        node.* = .{ .if_stmt = .{
            .condition = condition,
            .then_branch = then_branch,
            .else_branch = else_branch,
        } };
        return node;
    }
    pub fn createWhile(allocator: std.mem.Allocator, condition: *Expression, then_branch: Block) !*Statement {
        const node = try allocator.create(Statement);
        node.* = .{ .while_stmt = .{
            .condition = condition,
            .then_branch = then_branch,
        } };
        return node;
    }

    pub fn createReturn(allocator: std.mem.Allocator, value: ?*Expression) !*Statement {
        const node = try allocator.create(Statement);
        node.* = .{ .return_stmt = .{ .value = value } };
        return node;
    }

    pub fn createExpression(allocator: std.mem.Allocator, expr: *Expression) !*Statement {
        const node = try allocator.create(Statement);
        node.* = .{ .expression_stmt = expr };
        return node;
    }

    pub fn deinit(self: *Statement, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .var_dclr => |l| l.deinit(allocator),
            .if_stmt => |i| i.deinit(allocator),
            .while_stmt => |w| w.deinit(allocator),
            .assign_stmt => |a| a.deinit(allocator),
            .return_stmt => |r| r.deinit(allocator),
            .expression_stmt => |e| e.deinit(allocator),
        }
        allocator.destroy(self);
    }
};

pub const VarDeclr = struct {
    name: []const u8,
    type_annotation: ?[]const u8,
    value: *Expression,
    slot: ?u32 = null,
    is_mutable: bool,

    pub fn deinit(self: VarDeclr, allocator: std.mem.Allocator) void {
        self.value.deinit(allocator);
    }
};
pub const AssignStmt = struct {
    name: []const u8,
    value: *Expression,
    slot: ?u32 = null,

    pub fn deinit(self: AssignStmt, allocator: std.mem.Allocator) void {
        self.value.deinit(allocator);
    }
};

pub const ReturnStmt = struct {
    value: ?*Expression,

    pub fn deinit(self: ReturnStmt, allocator: std.mem.Allocator) void {
        if (self.value) |v|
            v.deinit(allocator);
    }
};

pub const IfStmt = struct {
    condition: *Expression,
    then_branch: Block,
    else_branch: ?Block,

    pub fn deinit(self: IfStmt, allocator: std.mem.Allocator) void {
        self.condition.deinit(allocator);
        self.then_branch.deinit(allocator);
        if (self.else_branch) |branch| branch.deinit(allocator);
    }
};

pub const WhileStmt = struct {
    condition: *Expression,
    then_branch: Block,

    pub fn deinit(self: WhileStmt, allocator: std.mem.Allocator) void {
        self.condition.deinit(allocator);
        self.then_branch.deinit(allocator);
    }
};
