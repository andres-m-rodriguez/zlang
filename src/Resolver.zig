const std = @import("std");
const Enviroment = @import("Structures/ScopeStack.zig").Enviroment;
const Ast = @import("Structures/Ast.zig");
const Self = @This();
pub const Error = error{
    UseBeforeInitialization,
    AssignToConst,
} || Enviroment.Error;

env: Enviroment,
pub fn init() Self {
    return .{ .env = .init() };
}
pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.env.deinit(allocator);
}
pub fn maxSlots(self: *const Self) u32 {
    return self.env.slots.max_slots;
}
pub fn resolve(self: *Self, allocator: std.mem.Allocator, ast: Ast.Block) Error!void {
    try self.env.beginScope(allocator);
    defer self.env.endScope(allocator);
    for (ast.statements) |statment| {
        try self.resolveStatment(allocator, statment);
    }
}

fn resolveStatment(self: *Self, allocator: std.mem.Allocator, statement: *Ast.Statement) Error!void {
    switch (statement.*) {
        .var_dclr => try self.resolveVarDeclr(allocator, statement),
        .assign_stmt => try self.resolveAssign(statement),
        .if_stmt => try self.resolveIfStmt(allocator, statement),
        .while_stmt => try self.resolveWhileStmt(allocator, statement),
        .expression_stmt => try self.resolveExpression(statement.expression_stmt),
        .return_stmt => |r| if (r.value) |v| try self.resolveExpression(v),
    }
}
fn resolveVarDeclr(self: *Self, allocator: std.mem.Allocator, statement: *Ast.Statement) Error!void {
    const var_dclr = &statement.var_dclr;
    try self.resolveExpression(var_dclr.value);
    const slot = try self.env.declare(allocator, var_dclr.name, var_dclr.is_mutable);
    var_dclr.slot = slot;
    try self.env.define(var_dclr.name);
}
fn resolveAssign(self: *Self, statement: *Ast.Statement) Error!void {
    const assign = &statement.assign_stmt;
    try self.resolveExpression(assign.value);
    const result = self.env.resolve(assign.name) orelse {
        return Error.UndeclaredVariable;
    };
    if (!result.binding.is_mutable) {
        return Error.AssignToConst;
    }
    assign.slot = result.binding.slot;
}
fn resolveIfStmt(self: *Self, allocator: std.mem.Allocator, statment: *Ast.Statement) Error!void {
    const if_stmt = &statment.if_stmt;
    try self.resolveExpression(if_stmt.condition);
    try self.resolveBlock(allocator, if_stmt.then_branch);
    if (if_stmt.else_branch) |else_branch| try self.resolveBlock(allocator, else_branch);
}
fn resolveWhileStmt(self: *Self, allocator: std.mem.Allocator, statement: *Ast.Statement) Error!void {
    const while_stmt = &statement.while_stmt;
    try self.resolveExpression(while_stmt.condition);
    try self.resolveBlock(allocator, while_stmt.then_branch);
}
fn resolveBlock(self: *Self, allocator: std.mem.Allocator, block: Ast.Block) Error!void {
    try self.env.beginScope(allocator);
    defer self.env.endScope(allocator);
    for (block.statements) |statment| {
        try self.resolveStatment(allocator, statment);
    }
}
fn resolveExpression(self: *Self, expr: *Ast.Expression) Error!void {
    switch (expr.*) {
        .literal => {},

        .identifier => |*ident| {
            const result = self.env.resolve(ident.name) orelse
                return Error.UndeclaredVariable;

            if (!result.binding.is_initialized) {
                return Error.UseBeforeInitialization;
            }
            ident.slot = result.binding.slot;
        },

        .binary => |b| {
            try self.resolveExpression(b.left);
            try self.resolveExpression(b.right);
        },

        .unary => |u| {
            try self.resolveExpression(u.operand);
        },

        .grouping => |inner| {
            try self.resolveExpression(inner);
        },
    }
}
