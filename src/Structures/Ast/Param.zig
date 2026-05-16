const std = @import("std");
const ZType = @import("ZType.zig");
const Self = @This();
param_name: []const u8,
param_type: ZType,
slot: ?u32 = null,
pub fn init(param_name: []const u8, param_type: ZType) Self {
    return .{
        .param_name = param_name,
        .param_type = param_type,
        .slot = null,
    };
}
