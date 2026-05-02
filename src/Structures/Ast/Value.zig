const std = @import("std");

pub const Value = union(enum) {
    number: f64,
    string: []const u8,
    boolean: bool,
    nil,

    pub fn createNumber(value: []const u8) !Value {
        const parsed = try std.fmt.parseFloat(f64, value);
        return .{ .number = parsed };
    }

    pub fn createString(value: []const u8) Value {
        return .{ .string = value };
    }

    pub fn createBoolean(value: bool) Value {
        return .{ .boolean = value };
    }

    pub fn createNil() Value {
        return .nil;
    }
};
