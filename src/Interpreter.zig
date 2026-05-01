const std = @import("std");
const Ast = @import("Structures/Ast.zig");
const Self = @This();

const EvalError = error{
    UnknownOperator,
    TypeMismatch,
    NotANumber,
    UndefinedVariable,
    OutOfMemory,
};

const Environment = struct {
    values: std.StringHashMapUnmanaged(Ast.Value),

    pub fn init() Environment {
        return .{ .values = .{} };
    }

    pub fn deinit(self: *Environment, allocator: std.mem.Allocator) void {
        self.values.deinit(allocator);
    }

    pub fn define(self: *Environment, allocator: std.mem.Allocator, name: []const u8, value: Ast.Value) !void {
        try self.values.put(allocator, name, value);
    }

    pub fn get(self: *Environment, name: []const u8) EvalError!Ast.Value {
        return self.values.get(name) orelse error.UndefinedVariable;
    }
};

env: Environment,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .env = Environment.init(),
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.env.deinit(self.allocator);
}

pub fn execute(self: *Self, statements: []*Ast.Statement, allocator: std.mem.Allocator) ![]const u8 {
    var last: f64 = 0;
    for (statements) |stmt| {
        last = try self.evalStatement(stmt);
    }
    return std.fmt.allocPrint(allocator, "{d}", .{last});
}

fn evalStatement(self: *Self, stmt: *Ast.Statement) EvalError!f64 {
    return switch (stmt.*) {
        .let => |l| try self.evalLet(l),
        .expression => |e| try self.eval(e),
    };
}

fn evalLet(self: *Self, l: Ast.LetStmt) EvalError!f64 {
    const value = try self.eval(l.value);
    try self.env.define(self.allocator, l.name, .{ .number = value });
    return value;
}

fn eval(self: *Self, expr: *Ast.Expression) EvalError!f64 {
    return switch (expr.*) {
        .literal => |v| try valueAsNumber(v),
        .identifier => |name| try valueAsNumber(try self.env.get(name)),
        .binary => |b| try self.evalBinary(b),
        .unary => |u| try self.evalUnary(u),
        .grouping => |g| try self.eval(g),
    };
}

fn evalBinary(self: *Self, b: Ast.BinaryExpr) EvalError!f64 {
    const left = try self.eval(b.left);
    const right = try self.eval(b.right);
    return switch (b.op) {
        .add => left + right,
        .sub => left - right,
        .mul => left * right,
        .div => left / right,
    };
}

fn evalUnary(self: *Self, u: Ast.UnaryExpr) EvalError!f64 {
    const operand = try self.eval(u.operand);
    return switch (u.op) {
        .negate => -operand,
    };
}

fn valueAsNumber(value: Ast.Value) EvalError!f64 {
    return switch (value) {
        .number => |n| n,
        else => error.NotANumber,
    };
}
