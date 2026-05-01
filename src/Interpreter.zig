const std = @import("std");
const Ast = @import("Structures/Ast.zig");
const Self = @This();
const EvalError = error{ UnknownOperator };

pub fn init() Self {
    return .{};
}

pub fn execute(self: *Self, node: *Ast.Node, allocator: std.mem.Allocator) ![]const u8 {
    const result = try self.eval(node);
    return std.fmt.allocPrint(allocator, "{d}", .{result});
}

fn eval(self: *Self, node: *Ast.Node) EvalError!f64  {
    return switch (node.value) {
        .number => |n| n,
        .string => |s| try self.evalBinary(node, s),
        else => unreachable,
    };
}

fn evalBinary(self: *Self, node: *Ast.Node, op: []const u8) EvalError!f64 {
    const left = try self.eval(node.left.?);
    const right = try self.eval(node.right.?);
    return switch (op[0]) {
        '+' => left + right,
        '-' => left - right,
        '*' => left * right,
        '/' => left / right,
        else => error.UnknownOperator,
    };
}
