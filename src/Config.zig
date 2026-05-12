const std = @import("std");

const Self = @This();

stack_size: u32 = 4096,

pub const Error = error{
    MalformedDirective,
    UnknownDirective,
    InvalidValue,
};

pub fn init() Self {
    return .{};
}

pub fn parse(self: *Self, source: []const u8) Error!void {
    var cursor: usize = 0;
    while (cursor < source.len) {
        const line_end = std.mem.indexOfScalarPos(u8, source, cursor, '\n') orelse source.len;
        const line = std.mem.trim(u8, source[cursor..line_end], " \t\r");
        if (line.len > 0 and line[0] == '#') {
            try self.applyDirective(line[1..]);
        }
        cursor = if (line_end < source.len) line_end + 1 else line_end;
    }
}

fn applyDirective(self: *Self, body: []const u8) Error!void {
    const colon = std.mem.indexOfScalar(u8, body, ':') orelse return Error.MalformedDirective;
    const name = std.mem.trim(u8, body[0..colon], " \t");
    const value = std.mem.trim(u8, body[colon + 1 ..], " \t\r");

    if (std.mem.eql(u8, name, "StackSize")) {
        self.stack_size = std.fmt.parseInt(u32, value, 10) catch return Error.InvalidValue;
        return;
    }
    return Error.UnknownDirective;
}
