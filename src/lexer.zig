const std = @import("std");
const LexerToken = @import("./LexerToken.zig");
const TokenKind = LexerToken.TokenKind;
const ascii = std.ascii;
const Self = @This();

source: []const u8,
cursor: usize,
pub fn init(source: []const u8) Self {
    return .{
        .source = source,
        .cursor = 0,
    };
}
pub fn advance() void {}

pub fn next(self: *Self) ?LexerToken {
    while (self.cursor < self.source.len and std.ascii.isWhitespace(self.source[self.cursor])) {
        self.cursor += 1;
    }
    if (self.cursor >= self.source.len)
        return null;
    const c = self.source[self.cursor .. self.cursor + 1];

    if (parseDigit(self.source[self.cursor..])) |NumberToken| {
        self.cursor += NumberToken.value.len;
        return NumberToken;
    }
    if (isOperator(c[0])) {
        self.cursor += 1;
        return LexerToken.init(c, TokenKind.Operator);
    }

    self.cursor += 1;
    return LexerToken.init(c, TokenKind.Unknown);
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
fn isOperator(value: u8) bool {
    return switch (value) {
        '+', '-', '*', '/', '=', '<', '>', '!', '&', '|', '^', '%' => true,
        else => false,
    };
}
