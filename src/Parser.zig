const std = @import("std");
const Lexer = @import("Lexer.zig");
const LexerToken = @import("LexerToken.zig");
const Ast = @import("./Structures/Ast.zig");

const Self = @This();
lexer: *Lexer,

pub const Error = error{
    UnexpectedEof,
    UnexpectedToken,
    ExpectedIdentifier,
    ExpectedEquals,
    ExpectedLBrace,
    ExpectedRBrace,
    InvalidNumber,
    OutOfMemory,
    InvalidAssignmentTarget,
    InvalidCharacter,
};

pub fn init(lexer: *Lexer) Self {
    return .{ .lexer = lexer };
}

pub fn parse(self: *Self, allocator: std.mem.Allocator) Error![]*Ast.Statement {
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

fn parseStatement(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Statement {
    const tok = self.lexer.peek() orelse return error.UnexpectedEof;
    switch (tok.token_kind) {
        .Let => return self.parseLet(allocator),
        .If => return self.parseIf(allocator),
        .While => return self.parseWhile(allocator),
        else => {},
    }
    const expr = try self.parseExpression(allocator);
    errdefer expr.deinit(allocator);

    if (self.lexer.peek()) |next_tok| {
        if (next_tok.token_kind == .Equal) {
            if (expr.* != .identifier) return Error.InvalidAssignmentTarget;
            const name = expr.identifier;
            expr.deinit(allocator);
            _ = self.lexer.next();
            const value = try self.parseExpression(allocator);
            return Ast.Statement.createAssign(allocator, name, value);
        }
    }

    return Ast.Statement.createExpression(allocator, expr);
}

fn parseLet(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Statement {
    _ = self.lexer.next(); // consume 'let'
    const ident = self.lexer.next() orelse return error.UnexpectedEof;
    if (ident.token_kind != .Identifier) return error.ExpectedIdentifier;
    const equal = self.lexer.next() orelse return error.UnexpectedEof;
    if (equal.token_kind != .Equal) return error.ExpectedEquals;
    const value = try self.parseExpression(allocator);
    return Ast.Statement.createLet(allocator, ident.value, null, value);
}

fn parseIf(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Statement {
    _ = self.lexer.next(); // consume 'if'
    const pl = self.lexer.next() orelse return Error.UnexpectedEof;
    if (pl.token_kind != LexerToken.TokenKind.LParen)
        return Error.UnexpectedToken;

    const condition = try self.parseExpression(allocator);
    errdefer condition.deinit(allocator);
    const pr = self.lexer.next() orelse return Error.UnexpectedEof;
    if (pr.token_kind != LexerToken.TokenKind.RParen)
        return Error.UnexpectedToken;

    const then_branch = try self.parseBlock(allocator);
    errdefer {
        for (then_branch) |s| s.deinit(allocator);
        allocator.free(then_branch);
    }

    var else_branch: ?[]*Ast.Statement = null;
    if (self.lexer.peek()) |tok| {
        if (tok.token_kind == .Else) {
            _ = self.lexer.next();
            else_branch = try self.parseBlock(allocator);
        }
    }
    errdefer if (else_branch) |branch| {
        for (branch) |s| s.deinit(allocator);
        allocator.free(branch);
    };

    return Ast.Statement.createIf(allocator, condition, then_branch, else_branch);
}

fn parseWhile(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Statement {
    _ = self.lexer.next(); // consume while
    const lp = self.lexer.next() orelse return Error.UnexpectedEof;
    if (lp.token_kind != LexerToken.TokenKind.LParen)
        return Error.UnexpectedToken;
    const condition = try self.parseExpression(allocator);
    errdefer condition.deinit(allocator);
    const rp = self.lexer.next() orelse return Error.UnexpectedEof;
    if (rp.token_kind != LexerToken.TokenKind.RParen)
        return Error.UnexpectedToken;
    const then_branch = try self.parseBlock(allocator);
    errdefer {
        for (then_branch) |s| s.deinit(allocator);
        allocator.free(then_branch);
    }

    return Ast.Statement.createWhile(allocator, condition, then_branch);
}

fn parseBlock(self: *Self, allocator: std.mem.Allocator) Error![]*Ast.Statement {
    const lbrace = self.lexer.next() orelse return error.UnexpectedEof;
    if (lbrace.token_kind != .LBrace) return error.ExpectedLBrace;

    var stmts: std.ArrayList(*Ast.Statement) = .empty;
    errdefer {
        for (stmts.items) |s| s.deinit(allocator);
        stmts.deinit(allocator);
    }

    while (self.lexer.peek()) |tok| {
        if (tok.token_kind == .RBrace) break;
        const stmt = try self.parseStatement(allocator);
        try stmts.append(allocator, stmt);
    }

    const rbrace = self.lexer.next() orelse return error.UnexpectedEof;
    if (rbrace.token_kind != .RBrace) return error.ExpectedRBrace;

    return stmts.toOwnedSlice(allocator);
}
fn parseExpression(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Expression {
    return self.parseEquality(allocator);
}

fn parseEquality(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Expression {
    var left = try self.parseAdditive(allocator);
    while (self.lexer.peek()) |tok| {
        const op: Ast.BinOp = switch (tok.token_kind) {
            .EqualEqual => .eq,
            .BangEqual => .neq,
            else => break,
        };
        _ = self.lexer.next();
        const right = try self.parseAdditive(allocator);
        left = try Ast.Expression.createBinary(allocator, op, left, right);
    }
    return left;
}

fn parseAdditive(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Expression {
    var left = try self.parseMultiplicative(allocator);
    while (self.lexer.peek()) |tok| {
        const op: Ast.BinOp = switch (tok.token_kind) {
            .Plus => .add,
            .Minus => .sub,
            else => break,
        };
        _ = self.lexer.next();
        const right = try self.parseMultiplicative(allocator);
        left = try Ast.Expression.createBinary(allocator, op, left, right);
    }
    return left;
}

fn parseMultiplicative(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Expression {
    var left = try self.parseUnary(allocator);
    while (self.lexer.peek()) |tok| {
        const op: Ast.BinOp = switch (tok.token_kind) {
            .Star => .mul,
            .Slash => .div,
            else => break,
        };
        _ = self.lexer.next();
        const right = try self.parseUnary(allocator);
        left = try Ast.Expression.createBinary(allocator, op, left, right);
    }
    return left;
}

fn parseUnary(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Expression {
    if (self.lexer.peek()) |tok| {
        if (tok.token_kind == .Minus) {
            _ = self.lexer.next();
            const operand = try self.parseUnary(allocator);
            return try Ast.Expression.createUnary(allocator, .negate, operand);
        }
    }
    return self.parsePrimary(allocator);
}

fn parsePrimary(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Expression {
    const tok = self.lexer.next() orelse return error.UnexpectedEof;
    return switch (tok.token_kind) {
        .Number => try Ast.Expression.createLiteral(allocator, try Ast.Value.createNumber(tok.value)),
        .True => try Ast.Expression.createLiteral(allocator, .{ .boolean = true }),
        .False => try Ast.Expression.createLiteral(allocator, .{ .boolean = false }),
        .Identifier => try Ast.Expression.createIdentifier(allocator, tok.value),
        .LParen => try self.parseGrouping(allocator),
        else => error.UnexpectedToken,
    };
}

fn parseGrouping(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Expression {
    const inner = try self.parseExpression(allocator);
    errdefer inner.deinit(allocator);
    const rparen = self.lexer.next() orelse return error.UnexpectedEof;
    if (rparen.token_kind != .RParen) return error.UnexpectedToken;
    return try Ast.Expression.createGrouping(allocator, inner);
}
