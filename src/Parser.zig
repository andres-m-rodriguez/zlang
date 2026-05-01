const std = @import("std");
const ascii = std.ascii;
const Lexer = @import("Lexer.zig");
const LexerToken = @import("LexerToken.zig");
const Ast = @import("./Structures/Ast.zig");
const Self = @This();

lexer: *Lexer,
pub fn init(lexer: *Lexer) Self {
    return .{ .lexer = lexer };
}

pub fn parse(self: *Self, allocator: std.mem.Allocator) !*Ast.Node {
    const left_val = try self.parseNumber();
    const op_val = self.parseOperator() orelse unreachable;
    const right_val = try self.parseNumber();

    const left = try allocator.create(Ast.Node);
    left.* = Ast.Node.init(left_val);

    const right = try allocator.create(Ast.Node);
    right.* = Ast.Node.init(right_val);

    const head = try allocator.create(Ast.Node);
    head.* = Ast.Node.init(op_val);
    head.left = left;
    head.right = right;
    return head;
}
fn parseOperator(self: *Self) ?Ast.Value {
    const next = self.lexer.next() orelse unreachable;
    if (next.token_kind != LexerToken.TokenKind.Operator) return null;

    return Ast.Value.createLiteral(next.value);
}
fn parseNumber(self: *Self) !Ast.Value {
    const next = self.lexer.next() orelse unreachable;
    return try Ast.Value.createNumber(next.value);
}
