const std = @import("std");
const Ast = @import("Structures/Ast.zig");
const ScopeStack = @import("ScopeStack.zig");
const Self = @This();

const Error = error{
    UnknownOperator,
    TypeMismatch,
    NotANumber,
    UndefinedVariable,
    OutOfMemory,
} || ScopeStack.Error;

env: ScopeStack,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .env = .empty,
        .allocator = allocator,
    };
}
pub fn deinit(self: *Self) void {
    self.env.deinit(self.allocator);
}

pub fn execute(self: *Self, statements: []*Ast.Statement, allocator: std.mem.Allocator) ![]const u8 {
    var last: Ast.Value = .nil;
    for (statements) |stmt| {
        last = try self.evalStatement(stmt, allocator);
    }
    return formatValue(allocator, last);
}

fn evalStatement(self: *Self, stmt: *Ast.Statement, allocator: std.mem.Allocator) Error!Ast.Value {
    return switch (stmt.*) {
        .let => |l| try self.evalLet(l),
        .expression => |e| try self.eval(e),
        .if_stmt => |i| try self.evalIf(i, allocator),
        .assign => |a| try self.evalAssign(a),
        .while_stmt => |w| try self.evalWhile(w, allocator),
    };
}

fn evalLet(self: *Self, l: Ast.LetStmt) Error!Ast.Value {
    const value = try self.eval(l.value);
    try self.env.define(self.allocator, l.name, value);

    return value;
}
fn evalAssign(self: *Self, a: Ast.AssignStmt) Error!Ast.Value {
    const value = try self.eval(a.value);
    try self.env.assign(self.allocator, a.name, value);

    return value;
}
fn evalIf(self: *Self, i: Ast.IfStmt, allocator: std.mem.Allocator) Error!Ast.Value {
    const condition = try self.eval(i.condition);
    const cond_bool = switch (condition) {
        .boolean => |b| b,
        else => return error.TypeMismatch,
    };

    if (cond_bool) {
        try self.env.push(allocator);
        for (i.then_branch) |s| {
            _ = try self.evalStatement(s, allocator);
        }
    } else if (i.else_branch) |branch| {
        for (branch) |s| {
            try self.env.push(allocator);
            _ = try self.evalStatement(s, allocator);
        }
    }
    self.env.pop(allocator);
    return .nil;
}
fn evalWhile(self: *Self, w: Ast.WhileStmt, allocator: std.mem.Allocator) Error!Ast.Value {
    var condition = try self.eval(w.condition);
    var cond_bool = switch (condition) {
        .boolean => |b| b,
        else => return Error.TypeMismatch,
    };
    while (cond_bool) {
        try self.env.push(allocator);
        for (w.then_branch) |s| {
            _ = try self.evalStatement(s, allocator);
        }
        self.env.pop(allocator);
        condition = try self.eval(w.condition);
        cond_bool = switch (condition) {
            .boolean => |b| b,
            else => return Error.TypeMismatch,
        };
    }
    return .nil;
}

fn eval(self: *Self, expr: *Ast.Expression) Error!Ast.Value {
    return switch (expr.*) {
        .literal => |v| v,
        .identifier => |name| try self.env.get(name),
        .binary => |b| try self.evalBinary(b),
        .unary => |u| try self.evalUnary(u),
        .grouping => |g| try self.eval(g),
    };
}

fn evalBinary(self: *Self, b: Ast.BinaryExpr) Error!Ast.Value {
    const left = try self.eval(b.left);
    const right = try self.eval(b.right);

    switch (b.op) {
        .eq => return .{ .boolean = valuesEqual(left, right) },
        .neq => return .{ .boolean = !valuesEqual(left, right) },
        else => {},
    }

    const ln = try valueAsNumber(left);
    const rn = try valueAsNumber(right);
    return switch (b.op) {
        .add => .{ .number = ln + rn },
        .sub => .{ .number = ln - rn },
        .mul => .{ .number = ln * rn },
        .div => .{ .number = ln / rn },
        .eq, .neq => unreachable,
    };
}
fn valuesEqual(a: Ast.Value, b: Ast.Value) bool {
    return switch (a) {
        .number => |an| switch (b) {
            .number => |bn| an == bn,
            else => false,
        },
        .boolean => |ab| switch (b) {
            .boolean => |bb| ab == bb,
            else => false,
        },
        .nil => switch (b) {
            .nil => true,
            else => false,
        },
        .string => |as| switch (b) {
            .string => |bs| std.mem.eql(u8, as, bs),
            else => false,
        },
    };
}
fn evalUnary(self: *Self, u: Ast.UnaryExpr) Error!Ast.Value {
    const operand = try self.eval(u.operand);
    const n = try valueAsNumber(operand);
    return switch (u.op) {
        .negate => .{ .number = -n },
    };
}

fn valueAsNumber(value: Ast.Value) Error!f64 {
    return switch (value) {
        .number => |n| n,
        else => error.NotANumber,
    };
}

fn formatValue(allocator: std.mem.Allocator, v: Ast.Value) ![]const u8 {
    return switch (v) {
        .number => |n| std.fmt.allocPrint(allocator, "{d}", .{n}),
        .string => |s| allocator.dupe(u8, s),
        .boolean => |b| allocator.dupe(u8, if (b) "true" else "false"),
        .nil => allocator.dupe(u8, "nil"),
    };
}
