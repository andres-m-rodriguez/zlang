const std = @import("std");
const Self = @This();

has_return: bool,
pub fn init() Self {
    return .{ .has_return = false };
}
