const std = @import("std");
const Lexer = @import("Lexer.zig");
const LexerToken = @import("LexerToken.zig");
const Ast = @import("Structures/Ast.zig");

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

pub fn parse(self: *Self, allocator: std.mem.Allocator) Error!Ast.Block {
    var statments: std.ArrayList(*Ast.Statement) = .empty;
    errdefer {
        for (statments.items) |s| s.deinit(allocator);
        statments.deinit(allocator);
    }
    while (self.lexer.peek()) |_| {
        const stmt = try self.parseStatement(allocator);
        try statments.append(allocator, stmt);
    }
    return .{ .statements = try statments.toOwnedSlice(allocator) };
}

fn parseStatement(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Statement {
    const tok = self.lexer.peek() orelse return unexpectedEof("parseStatement");
    switch (tok.token_kind) {
        .Var => return self.parseVar(allocator),
        .Const => return self.parseConst(allocator),
        .If => return self.parseIf(allocator),
        .While => return self.parseWhile(allocator),
        .Return => return self.parseReturn(allocator),
        .Fn => return self.parseFunction(allocator),
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
    const kw = self.lexer.next() orelse unreachable;
    std.debug.assert(kw.token_kind == .Const);
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
    const kw = self.lexer.next() orelse unreachable;
    std.debug.assert(kw.token_kind == .Var);
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
    const kw = self.lexer.next() orelse unreachable;
    std.debug.assert(kw.token_kind == .If);
    const pl = self.lexer.next() orelse return unexpectedEof("parseIf (LParen)");
    if (pl.token_kind != .LParen) return unexpected("parseIf (expected '(')", pl);

    const condition = try self.parseExpression(allocator);
    errdefer condition.deinit(allocator);
    const pr = self.lexer.next() orelse return unexpectedEof("parseIf (RParen)");
    if (pr.token_kind != .RParen) return unexpected("parseIf (expected ')')", pr);

    const then_branch = try self.parseBlock(allocator);
    errdefer then_branch.deinit(allocator);

    var else_branch: ?Ast.Block = null;
    if (self.lexer.peek()) |tok| {
        if (tok.token_kind == .Else) {
            _ = self.lexer.next();
            else_branch = try self.parseBlock(allocator);
        }
    }
    errdefer if (else_branch) |branch| branch.deinit(allocator);

    return Ast.Statement.createIf(allocator, condition, then_branch, else_branch);
}

fn parseWhile(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Statement {
    const kw = self.lexer.next() orelse unreachable;
    std.debug.assert(kw.token_kind == .While);
    const lp = self.lexer.next() orelse return unexpectedEof("parseWhile (LParen)");
    if (lp.token_kind != .LParen) return unexpected("parseWhile (expected '(')", lp);
    const condition = try self.parseExpression(allocator);
    errdefer condition.deinit(allocator);
    const rp = self.lexer.next() orelse return unexpectedEof("parseWhile (RParen)");
    if (rp.token_kind != .RParen) return unexpected("parseWhile (expected ')')", rp);
    const then_branch = try self.parseBlock(allocator);
    errdefer then_branch.deinit(allocator);

    return Ast.Statement.createWhile(allocator, condition, then_branch);
}
fn parseFunction(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Statement {
    var params: std.ArrayList(Ast.Param) = .empty;
    errdefer params.deinit(allocator);

    const kw = self.lexer.next() orelse unreachable; // consume 'fn'
    std.debug.assert(kw.token_kind == .Fn);
    const name = self.lexer.next() orelse return unexpectedEof("parseFn (FnName) ");
    if (name.token_kind != .Identifier)
        return unexpected("parseFn (FnName)", name);
    const lp = self.lexer.next() orelse return unexpectedEof("parseFn (LParen)");
    if (lp.token_kind != .LParen)
        return unexpected("parseFn (expected '(')", lp);

    var next_token = self.lexer.next() orelse return unexpectedEof("parseFn (Params)");
    while (next_token.token_kind != .RParen) {
        if (next_token.token_kind != .Identifier)
            return unexpected("parseFn (expected identifier for param name)", next_token);
        const param_name = next_token.value;
        const colon = self.lexer.next() orelse return unexpectedEof("parseFn (Colon in param)");
        if (colon.token_kind != .Colon)
            return unexpected("parseFn (expected ':' in param)", colon);
        const param_type = self.lexer.next() orelse return unexpectedEof("parseFn (Type in param)");
        if (param_type.token_kind != .Identifier)
            return unexpected("parseFn (expected identifier for param type)", param_type);

        try params.append(allocator, Ast.Param.init(
            param_name,
            Ast.ZType.fromAnnotation(param_type.value),
        ));

        next_token = self.lexer.next() orelse return unexpectedEof("parseFn (param separator)");
        if (next_token.token_kind == .RParen) break;
        if (next_token.token_kind != .Comma)
            return unexpected("parseFn (expected ',' or ')')", next_token);
        next_token = self.lexer.next() orelse return unexpectedEof("parseFn (after comma)");
    }

    const ret_type = self.lexer.next() orelse return unexpectedEof("parseFn (return type)");
    if (ret_type.token_kind != .Identifier)
        return unexpected("parseFn (expected return type)", ret_type);

    const body = try self.parseBlock(allocator);
    errdefer body.deinit(allocator);

    return Ast.Statement.createFunction(
        allocator,
        name.value,
        try params.toOwnedSlice(allocator),
        Ast.ZType.fromAnnotation(ret_type.value),
        body,
    );
}
fn parseReturn(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Statement {
    _ = self.lexer.next(); // consume 'return'

    const value: ?*Ast.Expression = if (self.hasReturnValue())
        try self.parseExpression(allocator)
    else
        null;

    return Ast.Statement.createReturn(allocator, value);
}

fn hasReturnValue(self: *Self) bool {
    const tok = self.lexer.peek() orelse return false;
    return switch (tok.token_kind) {
        .Var, .Const, .If, .While, .Return, .RBrace => false,
        else => true,
    };
}
fn parseBlock(self: *Self, allocator: std.mem.Allocator) Error!Ast.Block {
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

    return .{ .statements = try stmts.toOwnedSlice(allocator) };
}

fn parseExpression(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Expression {
    return self.parseEquality(allocator);
}

fn parseEquality(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Expression {
    var left = try self.parseComparison(allocator);
    while (self.lexer.peek()) |tok| {
        const op: Ast.BinOp = switch (tok.token_kind) {
            .EqualEqual => .Eq,
            .BangEqual => .Neq,
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
            .Greater => .Gt,
            .GreaterEqual => .Gte,
            .Less => .Lt,
            .LessEqual => .Lte,
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
            .Plus => .Add,
            .Minus => .Sub,
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
            .Star => .Mul,
            .Slash => .Div,
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
            return try Ast.Expression.createUnary(allocator, .Negate, operand);
        }
    }
    return self.parsePrimary(allocator);
}

fn parsePrimary(self: *Self, allocator: std.mem.Allocator) Error!*Ast.Expression {
    const tok = self.lexer.next() orelse return unexpectedEof("parsePrimary");
    return switch (tok.token_kind) {
        .Number => try Ast.Expression.createLiteral(allocator, try Ast.Value.createNumber(tok.value)),
        .String => try Ast.Expression.createLiteral(allocator, Ast.Value.createString(tok.value)),
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

const testing = std.testing;

fn parseFromSource(allocator: std.mem.Allocator, source: []const u8) Error!Ast.Block {
    var lex = Lexer.init(source);
    var parser = init(&lex);
    return parser.parse(allocator);
}

test "parser: var declaration with type and initializer" {
    const allocator = testing.allocator;
    const ast = try parseFromSource(allocator, "var x : i32 = 42");
    defer ast.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), ast.statements.len);
    const var_dclr = ast.statements[0].var_dclr;
    try testing.expectEqualStrings("x", var_dclr.name);
    try testing.expect(var_dclr.is_mutable);
    try testing.expectEqualStrings("i32", var_dclr.type.annotation.?);
    try testing.expectEqual(@as(f64, 42), var_dclr.value.literal.number);
}

test "parser: expression precedence binds * tighter than +" {
    const allocator = testing.allocator;
    const ast = try parseFromSource(allocator, "1 + 2 * 3");
    defer ast.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), ast.statements.len);
    const expr = ast.statements[0].expression_stmt;
    try testing.expectEqual(Ast.BinOp.Add, expr.binary.op);
    try testing.expectEqual(@as(f64, 1), expr.binary.left.literal.number);
    try testing.expectEqual(Ast.BinOp.Mul, expr.binary.right.binary.op);
    try testing.expectEqual(@as(f64, 2), expr.binary.right.binary.left.literal.number);
    try testing.expectEqual(@as(f64, 3), expr.binary.right.binary.right.literal.number);
}

test "parser: if/else parses both branches" {
    const allocator = testing.allocator;
    const ast = try parseFromSource(allocator, "if (true) { 1 } else { 2 }");
    defer ast.deinit(allocator);

    try testing.expectEqual(@as(usize, 1), ast.statements.len);
    const if_stmt = ast.statements[0].if_stmt;
    try testing.expect(if_stmt.condition.literal.boolean);
    try testing.expectEqual(@as(usize, 1), if_stmt.then_branch.statements.len);
    try testing.expect(if_stmt.else_branch != null);
    try testing.expectEqual(@as(usize, 1), if_stmt.else_branch.?.statements.len);
    try testing.expectEqual(@as(f64, 1), if_stmt.then_branch.statements[0].expression_stmt.literal.number);
    try testing.expectEqual(@as(f64, 2), if_stmt.else_branch.?.statements[0].expression_stmt.literal.number);
}
