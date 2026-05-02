const std = @import("std");
const LexerToken = @import("./LexerToken.zig");
const TokenKind = LexerToken.TokenKind;
const ascii = std.ascii;

const Self = @This();

source: []const u8,
cursor: usize,
current: ?LexerToken,
pub fn init(source: []const u8) Self {
    var self = Self{ .source = source, .cursor = 0, .current = null };
    self.current = self.scan();
    return self;
}

pub fn peek(self: *Self) ?LexerToken {
    return self.current;
}

pub fn next(self: *Self) ?LexerToken {
    const tok = self.current;
    self.current = self.scan();
    return tok;
}

pub fn scan(self: *Self) ?LexerToken {
    while (self.cursor < self.source.len and (ascii.isWhitespace(self.source[self.cursor]) or self.source[self.cursor] == ';')) {
        self.cursor += 1;
    }
    if (self.cursor >= self.source.len) return null;

    const c = self.source[self.cursor];

    if (parseDigit(self.source[self.cursor..])) |numberToken| {
        self.cursor += numberToken.value.len;
        return numberToken;
    }

    if (parseOperator(self.source[self.cursor..])) |operatorToken| {
        self.cursor += operatorToken.value.len;
        return operatorToken;
    }
    if (parseDelimiter(self.source[self.cursor..])) |tok| {
        self.cursor += tok.value.len;
        return tok;
    }

    if (ascii.isAlphabetic(c) or c == '_') {
        const start = self.cursor;
        while (self.cursor < self.source.len and isIdentCont(self.source[self.cursor])) {
            self.cursor += 1;
        }
        const word = self.source[start..self.cursor];
        if (keywordKind(word)) |kind| {
            return LexerToken.init(word, kind);
        }
        return LexerToken.init(word, .Identifier);
    }

    self.cursor += 1;
    const slice: []const u8 = &[_]u8{c};
    return LexerToken.init(slice, .Unknown);
}

fn parseDigit(value: []const u8) ?LexerToken {
    var idx: usize = 0;
    while (idx < value.len) : (idx += 1) {
        if (!ascii.isDigit(value[idx])) break;
    }
    if (idx == 0) return null;
    return LexerToken.init(value[0..idx], .Number);
}
fn isDelimiter(c: u8) bool {
    return switch (c) {
        '(',
        ')',
        '{',
        '}',
        => true,
        else => false,
    };
}
fn parseDelimiter(value: []const u8) ?LexerToken {
    if (value.len == 0) return null;
    const kind: TokenKind = switch (value[0]) {
        '(' => .LParen,
        ')' => .RParen,
        '{' => .LBrace,
        '}' => .RBrace,
        else => return null,
    };
    return LexerToken.init(value[0..1], kind);
}

fn parseOperator(value: []const u8) ?LexerToken {
    if (value.len == 0) return null;
    if (!isOperator(value[0])) return null;

    if (value.len >= 2) {
        const two = value[0..2];
        if (std.mem.eql(u8, two, "==")) return LexerToken.init(two, .EqualEqual);
        if (std.mem.eql(u8, two, "!=")) return LexerToken.init(two, .BangEqual);
        if (std.mem.eql(u8, two, "<=")) return LexerToken.init(two, .LessEqual);
        if (std.mem.eql(u8, two, ">=")) return LexerToken.init(two, .GreaterEqual);
    }

    const kind: TokenKind = switch (value[0]) {
        '+' => .Plus,
        '-' => .Minus,
        '*' => .Star,
        '/' => .Slash,
        '=' => .Equal,
        '<' => .Less,
        '>' => .Greater,
        '!' => .Bang,
        else => .Unknown,
    };
    return LexerToken.init(value[0..1], kind);
}

fn isIdentCont(c: u8) bool {
    return ascii.isAlphanumeric(c) or c == '_';
}

fn isOperator(value: u8) bool {
    return switch (value) {
        '+', '-', '*', '/', '=', '<', '>', '!', '&', '|', '^', '%' => true,
        else => false,
    };
}

fn keywordKind(value: []const u8) ?TokenKind {
    if (std.mem.eql(u8, value, "let")) return .Let;
    if (std.mem.eql(u8, value, "if")) return .If;
    if (std.mem.eql(u8, value, "else")) return .Else;
    if (std.mem.eql(u8, value, "while")) return .While;
    if (std.mem.eql(u8, value, "return")) return .Return;
    if (std.mem.eql(u8, value, "true")) return .True;
    if (std.mem.eql(u8, value, "false")) return .False;
    return null;
}
