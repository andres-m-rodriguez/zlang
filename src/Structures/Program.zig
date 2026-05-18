const std = @import("std");
const ByteCode = @import("Bytecode.zig");

const Self = @This();
pub const Function = struct {
    chunk: ByteCode,
    arity: u8,
    locals_count: u16,
    param_kinds: []ByteCode.PrimKind,
    return_kind: ByteCode.PrimKind,
    pub fn init(
        chunk: ByteCode,
        arity: u8,
        locals_count: u16,
        param_kinds: []ByteCode.PrimKind,
        return_kind: ByteCode.PrimKind,
    ) Function {
        return .{
            .chunk = chunk,
            .arity = arity,
            .locals_count = locals_count,
            .param_kinds = param_kinds,
            .return_kind = return_kind,
        };
    }
    pub fn deinit(
        self: *Function,
        allocator: std.mem.Allocator,
    ) void {
        self.chunk.deinit(allocator);
        allocator.free(self.param_kinds);
    }
};

main: ByteCode,
functions: []Function,
pub fn init() Self {
    return .{
        .main = .init(),
        .functions = &.{},
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.main.deinit(allocator);
    for (self.functions) |*func| {
        func.deinit(allocator);
    }
    allocator.free(self.functions);
}
