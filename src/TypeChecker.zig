const std = @import("std");
const Ast = @import("Structures/Ast.zig");
const ZType = @import("Structures/Ast/ZType.zig");
const Expression = @import("Structures/Ast/Expression.zig");
const BinOp = @import("Structures/Ast/Op.zig").BinOp;
const UnaryOp = @import("Structures/Ast/Op.zig").UnaryOp;
const TypeEnviroment = @import("TypeEnviroment.zig");
const Self = @This();

pub const Error = error{
    UnknownType,
    TypeMismatch,
    UndeclaredVariable,
    NonBooleanCondition,
    InvalidBinaryOperands,
    InvalidUnaryOperand,
    NilHasNoType,
    ArityMismatch,
    UnknownFunction,
    DuplicateFunction,
} || std.mem.Allocator.Error;

const FunctionTable = std.StringHashMapUnmanaged(*Ast.FnStmt);

env: TypeEnviroment,
functions: FunctionTable,
current_return_type: ?ZType.Kind,

pub fn init() Self {
    return .{
        .env = TypeEnviroment.init(),
        .functions = .empty,
        .current_return_type = null,
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.env.deinit(allocator);
    self.functions.deinit(allocator);
}

pub fn check(self: *Self, allocator: std.mem.Allocator, ast: Ast.Block) Error!void {
    try self.collectFunctions(allocator, ast);
    try self.env.beginScope(allocator);
    defer self.env.endScope(allocator);
    for (ast.statements) |statement| {
        try self.checkStatement(allocator, statement);
    }
}

fn collectFunctions(self: *Self, allocator: std.mem.Allocator, ast: Ast.Block) Error!void {
    for (ast.statements) |statement| {
        if (statement.* != .fn_stmt) continue;
        const fs = &statement.fn_stmt;
        if (fs.return_type.annotation) |annot| {
            fs.return_type.resolved = ZType.resolve(annot) orelse return Error.UnknownType;
        }
        for (fs.params) |*p| {
            if (p.param_type.annotation) |annot| {
                p.param_type.resolved = ZType.resolve(annot) orelse return Error.UnknownType;
            }
        }
        const result = try self.functions.getOrPut(allocator, fs.name);
        if (result.found_existing) return Error.DuplicateFunction;
        result.value_ptr.* = fs;
    }
}

fn checkStatement(self: *Self, allocator: std.mem.Allocator, stmt: *Ast.Statement) Error!void {
    switch (stmt.*) {
        .var_dclr => try self.checkVarDeclr(allocator, stmt),
        .assign_stmt => try self.checkAssign(stmt),
        .if_stmt => try self.checkIf(allocator, stmt),
        .while_stmt => try self.checkWhile(allocator, stmt),
        .return_stmt => |r| {
            if (r.value) |v| {
                const ret_kind = try self.typeOfExpression(v);
                if (self.current_return_type) |expected| {
                    if (!std.meta.eql(expected, ret_kind)) return Error.TypeMismatch;
                }
            }
        },
        .expression_stmt => |e| {
            _ = try self.typeOfExpression(e);
        },
        .fn_stmt => try self.checkFnStmt(allocator, stmt),
    }
}

fn checkFnStmt(self: *Self, allocator: std.mem.Allocator, stmt: *Ast.Statement) Error!void {
    const fs = &stmt.fn_stmt;
    try self.env.beginScope(allocator);
    defer self.env.endScope(allocator);
    for (fs.params) |p| {
        try self.declareLocal(allocator, p.param_name, p.param_type.resolved.?);
    }
    const prev = self.current_return_type;
    defer self.current_return_type = prev;
    self.current_return_type = fs.return_type.resolved;
    try self.checkBlock(allocator, fs.body);
}

fn checkVarDeclr(self: *Self, allocator: std.mem.Allocator, stmt: *Ast.Statement) Error!void {
    const var_dclr = &stmt.var_dclr;

    if (var_dclr.type.annotation) |annot| {
        var_dclr.type.resolved = ZType.resolve(annot) orelse return Error.UnknownType;
    }

    const value_kind = try self.typeOfExpression(var_dclr.value);

    if (var_dclr.type.resolved) |declared| {
        if (!std.meta.eql(declared, value_kind)) return Error.TypeMismatch;
    } else {
        var_dclr.type.resolved = value_kind;
    }

    try self.declareLocal(allocator, var_dclr.name, var_dclr.type.resolved.?);
}

fn checkAssign(self: *Self, stmt: *Ast.Statement) Error!void {
    const assign = &stmt.assign_stmt;
    const declared = self.env.lookup(assign.name) orelse return Error.UndeclaredVariable;
    const value_kind = try self.typeOfExpression(assign.value);
    if (!std.meta.eql(declared, value_kind)) return Error.TypeMismatch;
}

fn checkIf(self: *Self, allocator: std.mem.Allocator, stmt: *Ast.Statement) Error!void {
    const if_stmt = stmt.if_stmt;
    const cond_kind = try self.typeOfExpression(if_stmt.condition);
    if (cond_kind != .Bool) return Error.NonBooleanCondition;
    try self.checkBlock(allocator, if_stmt.then_branch);
    if (if_stmt.else_branch) |branch| try self.checkBlock(allocator, branch);
}

fn checkWhile(self: *Self, allocator: std.mem.Allocator, stmt: *Ast.Statement) Error!void {
    const while_stmt = stmt.while_stmt;
    const cond_kind = try self.typeOfExpression(while_stmt.condition);
    if (cond_kind != .Bool) return Error.NonBooleanCondition;
    try self.checkBlock(allocator, while_stmt.then_branch);
}

fn checkBlock(self: *Self, allocator: std.mem.Allocator, block: Ast.Block) Error!void {
    try self.env.beginScope(allocator);
    defer self.env.endScope(allocator);
    for (block.statements) |statement| {
        try self.checkStatement(allocator, statement);
    }
}

fn declareLocal(self: *Self, allocator: std.mem.Allocator, name: []const u8, kind: ZType.Kind) Error!void {
    try self.env.declare(allocator, name, kind);
}
fn typeOfExpression(self: *Self, expr: *Expression.Expression) Error!ZType.Kind {
    return switch (expr.*) {
        .literal => |v| switch (v) {
            .number => .{ .numeric = .Int },
            .boolean => .Bool,
            .string => .String,
            .nil => return Error.NilHasNoType,
        },
        .identifier => |id| self.env.lookup(id.name) orelse return Error.UndeclaredVariable,
        .binary => |b| self.typeOfBinary(b),
        .unary => |u| self.typeOfUnary(u),
        .grouping => |inner| self.typeOfExpression(inner),
        .call => |c| self.typeOfCall(c),
    };
}

fn typeOfCall(self: *Self, c: Expression.CallExpr) Error!ZType.Kind {
    const fs = self.functions.get(c.callee) orelse return Error.UnknownFunction;
    if (c.args.len != fs.params.len) return Error.ArityMismatch;
    for (c.args, fs.params) |arg, param| {
        const arg_kind = try self.typeOfExpression(arg);
        const expected = param.param_type.resolved.?;
        if (!std.meta.eql(arg_kind, expected)) return Error.TypeMismatch;
    }
    return fs.return_type.resolved.?;
}

fn typeOfBinary(self: *Self, b: Expression.BinaryExpr) Error!ZType.Kind {
    const left_kind = try self.typeOfExpression(b.left);
    const right_kind = try self.typeOfExpression(b.right);
    return checkBinaryOp(b.op, left_kind, right_kind);
}

fn typeOfUnary(self: *Self, u: Expression.UnaryExpr) Error!ZType.Kind {
    const operand_kind = try self.typeOfExpression(u.operand);
    return checkUnaryOp(u.op, operand_kind);
}

fn asNumericBinary(kind: ZType.Kind) Error!ZType.Numeric {
    return switch (kind) {
        .numeric => |n| n,
        else => Error.InvalidBinaryOperands,
    };
}

fn asNumericUnary(kind: ZType.Kind) Error!ZType.Numeric {
    return switch (kind) {
        .numeric => |n| n,
        else => Error.InvalidUnaryOperand,
    };
}

fn checkBinaryOp(op: BinOp, left: ZType.Kind, right: ZType.Kind) Error!ZType.Kind {
    return switch (op) {
        .Add, .Sub, .Mul, .Div => {
            const ln = try asNumericBinary(left);
            const rn = try asNumericBinary(right);
            if (ln != rn) return Error.InvalidBinaryOperands;
            return .{ .numeric = ln };
        },
        .Lt, .Lte, .Gt, .Gte => {
            const ln = try asNumericBinary(left);
            const rn = try asNumericBinary(right);
            if (ln != rn) return Error.InvalidBinaryOperands;
            return .Bool;
        },
        .Eq, .Neq => {
            if (left == .String or right == .String) return Error.InvalidBinaryOperands;
            if (!std.meta.eql(left, right)) return Error.InvalidBinaryOperands;
            return .Bool;
        },
    };
}

fn checkUnaryOp(op: UnaryOp, operand: ZType.Kind) Error!ZType.Kind {
    return switch (op) {
        .Negate => {
            _ = try asNumericUnary(operand);
            return operand;
        },
    };
}
