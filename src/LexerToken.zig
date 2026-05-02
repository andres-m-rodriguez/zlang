const std = @import("std");
const Self = @This();

value: []const u8,
token_kind: TokenKind,

pub fn init(value: []const u8, token_kind: TokenKind) Self {
    return .{
        .value = value,
        .token_kind = token_kind,
    };
}

pub const TokenKind = enum {
    Number,
    Identifier,
    Unknown,

    // Keywords
    Let,
    If,
    Else,
    While,
    Return,
    True,
    False,

    // Operators
    Plus,
    Minus,
    Star,
    Slash,
    Equal,
    EqualEqual,
    Bang,
    BangEqual,
    Less,
    LessEqual,
    Greater,
    GreaterEqual,

    // Punctuation
    LParen,
    RParen,
    LBrace,
    RBrace,
};
