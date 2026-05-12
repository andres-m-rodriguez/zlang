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

pub const Context = struct {
    pub fn hash(_: Context, v: Value) u64 {
        var h = std.hash.Wyhash.init(0);
        switch (v) {
            .number => |n| {
                h.update(&[_]u8{0});
                h.update(&std.mem.toBytes(n));
            },
            .string => |s| {
                h.update(&[_]u8{1});
                h.update(s);
            },
            .boolean => |b| {
                h.update(&[_]u8{ 2, @intFromBool(b) });
            },
            .nil => {
                h.update(&[_]u8{3});
            },
        }
        return h.final();
    }

    pub fn eql(_: Context, a: Value, b: Value) bool {
        return switch (a) {
            .number => switch (b) {
                .number => @as(u64, @bitCast(a.number)) == @as(u64, @bitCast(b.number)), // Holy
                else => false,
            },
            .string => |as| switch (b) {
                .string => |bs| std.mem.eql(u8, as, bs),
                else => false,
            },
            .boolean => |ab| switch (b) {
                .boolean => |bb| ab == bb,
                else => false,
            },
            .nil => b == .nil,
        };
    }
};
