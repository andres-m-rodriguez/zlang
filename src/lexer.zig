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
    while (self.cursor < self.source.len and std.ascii.isWhitespace(self.source[self.cursor])) {
        self.cursor += 1;
    }
    if (self.cursor >= self.source.len)
        return null;
    const c = self.source[self.cursor];

    if (parseDigit(self.source[self.cursor..])) |NumberToken| {
        self.cursor += NumberToken.value.len;
        return NumberToken;
    }
    if (parseOperator(self.source[self.cursor..])) |tok| {
        self.cursor += tok.value.len;
        return tok;
    }

    if (std.ascii.isAlphabetic(c) or c == '_') {
        const start = self.cursor;
        while (self.cursor < self.source.len and isIdentCont(self.source[self.cursor])) {
            self.cursor += 1;
        }
        const word = self.source[start..self.cursor];

        if (isKeyword(word)) {
            return LexerToken.init(word, .Keyword);
        }

        return LexerToken.init(word, .Identifier);
    }

    self.cursor += 1;
    const slice: []const u8 = &[_]u8{c};
    return LexerToken.init(slice, TokenKind.Unknown);
}
fn parseDigit(value: []const u8) ?LexerToken {
    var idx: usize = 0;
    while (idx < value.len) : (idx += 1) {
        if (ascii.isDigit(value[idx]) == false) {
            break;
        }
    }
    if (idx == 0)
        return null;

    return LexerToken.init(value[0..idx], TokenKind.Number);
}
fn parseOperator(value: []const u8) ?LexerToken {
    if (value.len == 0) return null;
    if (!isOperator(value[0])) return null;
    return LexerToken.init(value[0..1], TokenKind.Operator);
}
fn isIdentCont(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}
fn isOperator(value: u8) bool {
    return switch (value) {
        '+', '-', '*', '/', '=', '<', '>', '!', '&', '|', '^', '%' => true,
        else => false,
    };
}
fn isKeyword(value: []const u8) bool {
    const keywords = [_][]const u8{ "let", "if", "while", "return" };
    for (keywords) |kw| {
        if (std.mem.eql(u8, value, kw)) return true;
    }
    return false;
}
