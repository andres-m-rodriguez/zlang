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

fn unexpected(ctx: []const u8, tok: LexerToken) Error {
    std.debug.print(
        "[parser] {s}: unexpected token kind={s} value=\"{s}\"\n",
        .{ ctx, @tagName(tok.token_kind), tok.value },
    );
    return Error.UnexpectedToken;
}

fn unexpectedEof(ctx: []const u8) Error {
    std.debug.print("[parser] {s}: unexpected EOF\n", .{ctx});
    return Error.UnexpectedEof;
}

fn expectedIdent(ctx: []const u8, tok: LexerToken) Error {
    std.debug.print(
        "[parser] {s}: expected identifier, got kind={s} value=\"{s}\"\n",
        .{ ctx, @tagName(tok.token_kind), tok.value },
    );
    return Error.ExpectedIdentifier;
}

fn expectedEquals(ctx: []const u8, tok: LexerToken) Error {
    std.debug.print(
        "[parser] {s}: expected '=', got kind={s} value=\"{s}\"\n",
        .{ ctx, @tagName(tok.token_kind), tok.value },
    );
    return Error.ExpectedEquals;
}

fn expectedLBrace(ctx: []const u8, tok: LexerToken) Error {
    std.debug.print(
        "[parser] {s}: expected '{{', got kind={s} value=\"{s}\"\n",
        .{ ctx, @tagName(tok.token_kind), tok.value },
    );
    return Error.ExpectedLBrace;
}

fn expectedRBrace(ctx: []const u8, tok: LexerToken) Error {
    std.debug.print(
        "[parser] {s}: expected '}}', got kind={s} value=\"{s}\"\n",
        .{ ctx, @tagName(tok.token_kind), tok.value },
    );
    return Error.ExpectedRBrace;
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
    const tok = self.lexer.peek() orelse return unexpectedEof("parseStatement");
    switch (tok.token_kind) {
        .Var => return self.parseVar(allocator),
        .Const => return self.parseConst(allocator),
        .If => return self.parseIf(allocator),
        .While => return self.parseWhile(allocator),
        else => {},
    }
    const expr = try self.parseExpression(allocator);
    errdefer expr.deinit(allocator);

    if (self.lexer.peek()) |next_tok| {
        if (next_tok.token_kind == .Equal) {
            if (expr.* != .identifier) {
                std.debug.print("[parser] parseStatement: invalid assignment target\n", .{});
                return Error.InvalidAssignmentTarget;
            }
            const name = expr.identifier.name;
            expr.deinit(allocator);
            _ = self.lexer.next();
            const value = try self.parseExpression(allocator);
            return Ast.Statement.createAssign(allocator, name, value);
        }
    }

    return Ast.Statement.createExpression(allocator, expr);
}

fn parseConst(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Statement {
    _ = self.lexer.next(); // consume 'const'
    const ident = self.lexer.next() orelse return unexpectedEof("parseConst (ident)");
    if (ident.token_kind != .Identifier) return expectedIdent("parseConst", ident);
    const colon = self.lexer.next() orelse return unexpectedEof("parseConst (colon)");
    if (colon.token_kind != .Colon) return unexpected("parseConst (expected ':')", colon);
    const type_id = self.lexer.next() orelse return unexpectedEof("parseConst (type)");
    if (type_id.token_kind != .Identifier) return unexpected("parseConst (expected type)", type_id);
    const equal = self.lexer.next() orelse return unexpectedEof("parseConst (equal)");
    if (equal.token_kind != .Equal) return expectedEquals("parseConst", equal);
    const value = try self.parseExpression(allocator);

    return Ast.Statement.createConst(allocator, ident.value, type_id.value, value);
}

fn parseVar(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Statement {
    _ = self.lexer.next(); // consume 'var'
    const ident = self.lexer.next() orelse return unexpectedEof("parseVar (ident)");
    if (ident.token_kind != .Identifier) return expectedIdent("parseVar", ident);
    const colon = self.lexer.next() orelse return unexpectedEof("parseVar (colon)");
    if (colon.token_kind != .Colon) return unexpected("parseVar (expected ':')", colon);
    const type_id = self.lexer.next() orelse return unexpectedEof("parseVar (type)");
    if (type_id.token_kind != .Identifier) return unexpected("parseVar (expected type)", type_id);
    const equal = self.lexer.next() orelse return unexpectedEof("parseVar (equal)");
    if (equal.token_kind != .Equal) return expectedEquals("parseVar", equal);
    const value = try self.parseExpression(allocator);

    return Ast.Statement.createVar(allocator, ident.value, type_id.value, value);
}

fn parseIf(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Statement {
    _ = self.lexer.next(); // consume 'if'
    const pl = self.lexer.next() orelse return unexpectedEof("parseIf (LParen)");
    if (pl.token_kind != .LParen) return unexpected("parseIf (expected '(')", pl);

    const condition = try self.parseExpression(allocator);
    errdefer condition.deinit(allocator);
    const pr = self.lexer.next() orelse return unexpectedEof("parseIf (RParen)");
    if (pr.token_kind != .RParen) return unexpected("parseIf (expected ')')", pr);

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
    const lp = self.lexer.next() orelse return unexpectedEof("parseWhile (LParen)");
    if (lp.token_kind != .LParen) return unexpected("parseWhile (expected '(')", lp);
    const condition = try self.parseExpression(allocator);
    errdefer condition.deinit(allocator);
    const rp = self.lexer.next() orelse return unexpectedEof("parseWhile (RParen)");
    if (rp.token_kind != .RParen) return unexpected("parseWhile (expected ')')", rp);
    const then_branch = try self.parseBlock(allocator);
    errdefer {
        for (then_branch) |s| s.deinit(allocator);
        allocator.free(then_branch);
    }

    return Ast.Statement.createWhile(allocator, condition, then_branch);
}

fn parseBlock(self: *Self, allocator: std.mem.Allocator) Error![]*Ast.Statement {
    const lbrace = self.lexer.next() orelse return unexpectedEof("parseBlock (LBrace)");
    if (lbrace.token_kind != .LBrace) return expectedLBrace("parseBlock", lbrace);

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

    const rbrace = self.lexer.next() orelse return unexpectedEof("parseBlock (RBrace)");
    if (rbrace.token_kind != .RBrace) return expectedRBrace("parseBlock", rbrace);

    return stmts.toOwnedSlice(allocator);
}

fn parseExpression(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Expression {
    return self.parseEquality(allocator);
}

fn parseEquality(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Expression {
    var left = try self.parseComparison(allocator);
    while (self.lexer.peek()) |tok| {
        const op: Ast.BinOp = switch (tok.token_kind) {
            .EqualEqual => .eq,
            .BangEqual => .neq,
            else => break,
        };
        _ = self.lexer.next();
        const right = try self.parseComparison(allocator);
        left = try Ast.Expression.createBinary(allocator, op, left, right);
    }
    return left;
}

fn parseComparison(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Expression {
    var left = try self.parseAdditive(allocator);
    while (self.lexer.peek()) |tok| {
        const op: Ast.BinOp = switch (tok.token_kind) {
            .Greater => .gt,
            .GreaterEqual => .gte,
            .Less => .lt,
            .LessEqual => .lte,
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
    const tok = self.lexer.next() orelse return unexpectedEof("parsePrimary");
    return switch (tok.token_kind) {
        .Number => try Ast.Expression.createLiteral(allocator, try Ast.Value.createNumber(tok.value)),
        .True => try Ast.Expression.createLiteral(allocator, .{ .boolean = true }),
        .False => try Ast.Expression.createLiteral(allocator, .{ .boolean = false }),
        .Identifier => try Ast.Expression.createIdentifier(allocator, tok.value),
        .LParen => try self.parseGrouping(allocator),
        else => unexpected("parsePrimary", tok),
    };
}

fn parseGrouping(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Expression {
    const inner = try self.parseExpression(allocator);
    errdefer inner.deinit(allocator);
    const rparen = self.lexer.next() orelse return unexpectedEof("parseGrouping");
    if (rparen.token_kind != .RParen) return unexpected("parseGrouping (expected ')')", rparen);
    return try Ast.Expression.createGrouping(allocator, inner);
}
