const std = @import("std");

const Self = @This();

stack_size: u32 = 4096,

pub const Result = struct {
    config: Self,
    rest: []const u8,
};

pub const Error = error{
    MalformedDirective,
    UnknownDirective,
    InvalidValue,
};

pub fn parse(source: []const u8) Error!Result {
    var config: Self = .{};
    var cursor: usize = 0;
    while (cursor < source.len) {
        cursor = skipBlankLines(source, cursor);
        if (cursor >= source.len or source[cursor] != '#') break;
        cursor = try parseDirective(&config, source, cursor);
    }
    return .{ .config = config, .rest = source[cursor..] };
}

fn skipBlankLines(source: []const u8, start: usize) usize {
    var cursor = start;
    while (cursor < source.len) {
        const c = source[cursor];
        if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
            cursor += 1;
        } else break;
    }
    return cursor;
}

fn parseDirective(config: *Self, source: []const u8, start: usize) Error!usize {
    var cursor = start + 1; // skip '#'
    const name_start = cursor;
    while (cursor < source.len and source[cursor] != ':' and source[cursor] != '\n') {
        cursor += 1;
    }
    if (cursor >= source.len or source[cursor] != ':') return Error.MalformedDirective;
    const name = std.mem.trim(u8, source[name_start..cursor], " \t");
    cursor += 1; // skip ':'

    const value_start = cursor;
    while (cursor < source.len and source[cursor] != '\n') cursor += 1;
    const value = std.mem.trim(u8, source[value_start..cursor], " \t\r");

    try applyDirective(config, name, value);
    if (cursor < source.len and source[cursor] == '\n') cursor += 1;
    return cursor;
}

fn applyDirective(config: *Self, name: []const u8, value: []const u8) Error!void {
    if (std.mem.eql(u8, name, "StackSize")) {
        config.stack_size = std.fmt.parseInt(u32, value, 10) catch return Error.InvalidValue;
        return;
    }
    return Error.UnknownDirective;
}
