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
    Operator,
    Unknown,
};

