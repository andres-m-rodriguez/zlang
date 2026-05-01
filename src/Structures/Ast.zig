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
    pub fn createLiteral(value: []const u8) Value {
        return .{ .string = value };
    }
};

pub const Node = struct {
    value: Value,
    left: ?*Node,
    right: ?*Node,

    pub fn init(token: Value) Node {
        return .{
            .value = token,
            .left = null,
            .right = null,
        };
    }
    pub fn deinit(node: *Node, allocator: std.mem.Allocator) void {
        if (node.left) |left| left.deinit(allocator);
        if (node.right) |right| right.deinit(allocator);
        allocator.destroy(node);
    }
};
