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
    var last: Ast.Value = .nil;
    for (statements) |stmt| {
        last = try self.evalStatement(stmt);
    }
    return formatValue(allocator, last);
}

fn evalStatement(self: *Self, stmt: *Ast.Statement) EvalError!Ast.Value {
    return switch (stmt.*) {
        .let => |l| try self.evalLet(l),
        .expression => |e| try self.eval(e),
    };
}

fn evalLet(self: *Self, l: Ast.LetStmt) EvalError!Ast.Value {
    const value = try self.eval(l.value);
    try self.env.define(self.allocator, l.name, value);
    return value;
}

fn eval(self: *Self, expr: *Ast.Expression) EvalError!Ast.Value {
    return switch (expr.*) {
        .literal => |v| v,
        .identifier => |name| try self.env.get(name),
        .binary => |b| try self.evalBinary(b),
        .unary => |u| try self.evalUnary(u),
        .grouping => |g| try self.eval(g),
    };
}

fn evalBinary(self: *Self, b: Ast.BinaryExpr) EvalError!Ast.Value {
    const left = try self.eval(b.left);
    const right = try self.eval(b.right);
    const ln = try valueAsNumber(left);
    const rn = try valueAsNumber(right);
    return switch (b.op) {
        .add => .{ .number = ln + rn },
        .sub => .{ .number = ln - rn },
        .mul => .{ .number = ln * rn },
        .div => .{ .number = ln / rn },
    };
}

fn evalUnary(self: *Self, u: Ast.UnaryExpr) EvalError!Ast.Value {
    const operand = try self.eval(u.operand);
    const n = try valueAsNumber(operand);
    return switch (u.op) {
        .negate => .{ .number = -n },
    };
}

fn valueAsNumber(value: Ast.Value) EvalError!f64 {
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
