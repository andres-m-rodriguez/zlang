const std = @import("std");
const Self = @This();

slot: u16,
is_mutable: bool,
is_initialized: bool,
pub fn init() Self {
    return .{};
}
