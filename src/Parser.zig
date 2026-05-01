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

pub fn parse(self: *Self, allocator: std.mem.Allocator) ![]*Ast.Statement {
    var statments: std.ArrayList(*Ast.Statement) = .empty;
    errdefer {
        for (statments.items) |s| s.deinit(allocator);
        statments.deinit(allocator);
    }

    while (self.lexer.peek()) |_| {
        const stmt = try self.parseStatement(allocator);
        try statments.append(allocator, stmt);
    }

    return try statments.toOwnedSlice(allocator);
}

fn parseStatement(self: *Self, allocator: std.mem.Allocator) !*Ast.Statement {
    const tok = self.lexer.peek() orelse return error.UnexpectedEof;
    if (tok.token_kind == .Keyword and std.mem.eql(u8, tok.value, "let")) {
        return self.parseLet(allocator);
    }
    const expr = try self.parseExpression(allocator);
    return Ast.Statement.createExpression(allocator, expr);
}
fn parseLet(self: *Self, allocator: std.mem.Allocator) !*Ast.Statement {
    _ = self.lexer.next(); // consume 'let'

    const ident = self.lexer.next() orelse return error.UnexpectedEof;
    if (ident.token_kind != .Identifier) return error.ExpectedIdentifier;

    const equal = self.lexer.next() orelse return error.UnexpectedEof;
    if (equal.token_kind != .Operator or equal.value.len != 1 or equal.value[0] != '=') {
        return error.ExpectedEquals;
    }

    const value = try self.parseExpression(allocator);
    return Ast.Statement.createLet(allocator, ident.value, null, value);
}

fn parseExpression(self: *Self, allocator: std.mem.Allocator) !*Ast.Expression {
    var left = try self.parseUnary(allocator);
    while (self.lexer.peek()) |tok| {
        if (tok.token_kind != .Operator) break;
        _ = self.lexer.next();
        const right = try self.parseUnary(allocator);
        left = try Ast.Expression.createBinary(allocator, opFromToken(tok), left, right);
    }
    return left;
}
fn parseUnary(self: *Self, allocator: std.mem.Allocator) !*Ast.Expression {
    if (self.lexer.peek()) |tok| {
        if (tok.token_kind == .Operator and tok.value[0] == '-') {
            _ = self.lexer.next();
            const operand = try self.parseUnary(allocator);
            return try Ast.Expression.createUnary(allocator, .negate, operand);
        }
    }
    return self.parsePrimary(allocator);
}

fn parsePrimary(self: *Self, allocator: std.mem.Allocator) !*Ast.Expression {
    const tok = self.lexer.next() orelse return error.UnexpectedEof;
    return switch (tok.token_kind) {
        .Number => try Ast.Expression.createLiteral(allocator, try Ast.Value.createNumber(tok.value)),
        .Identifier => try Ast.Expression.createIdentifier(allocator, tok.value),
        else => error.UnexpectedToken,
    };
}
fn opFromToken(tok: LexerToken) Ast.BinOp {
    return switch (tok.value[0]) {
        '+' => .add,
        '-' => .sub,
        '*' => .mul,
        '/' => .div,
        else => unreachable,
    };
}
