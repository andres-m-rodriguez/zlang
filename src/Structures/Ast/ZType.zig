const std = @import("std");
const Self = @This();

pub const Kind = union(enum) {
    numeric: Numeric,
    Bool,
    String,
    Nil,
};
pub const Numeric = enum {
    Int,
    Float,
};
annotation: ?[]const u8,
resolved: ?Kind = null,

pub fn fromAnnotation(annotation: []const u8) Self {
    return .{ .annotation = annotation, .resolved = null };
}

pub fn unannotated() Self {
    return .{ .annotation = null, .resolved = null };
}

pub fn resolve(annotation: []const u8) ?Kind {
    if (std.mem.eql(u8, annotation, "int")) return .{ .numeric = .Int };
    if (std.mem.eql(u8, annotation, "float")) return .{ .numeric = .Float };
    if (std.mem.eql(u8, annotation, "bool")) return .Bool;
    if (std.mem.eql(u8, annotation, "str")) return .String;
    if (std.mem.eql(u8, annotation, "nil")) return .Nil;
    return null;
}
