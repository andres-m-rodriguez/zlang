const std = @import("std");
const Value = @import("Structures/Ast.zig").Value;
const Bytecode = @import("Structures/Bytecode.zig");
const Program = @import("Structures/Program.zig");
const FrameStore = @import("VirtualMachine/FrameStore.zig");
const Self = @This();

pub const Result = union(enum) {
    F64: f64,
    Bool: bool,
    Void,
};

stack: []u8,
sp: usize,
frames: FrameStore,
program: *const Program,

pub fn init(
    allocator: std.mem.Allocator,
    stack_size: usize,
    max_frames: usize,
    locals_pool_size: usize,
    program: *const Program,
) !Self {
    return .{
        .stack = try allocator.alloc(u8, stack_size),
        .sp = 0,
        .frames = try FrameStore.init(allocator, max_frames, locals_pool_size),
        .program = program,
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.free(self.stack);
    self.frames.deinit(allocator);
}

pub fn run(self: *Self, main_locals_count: u16) !Result {
    try self.frames.push(&self.program.main, main_locals_count);

    while (true) {
        const frame = self.frames.current();
        const op = frame.chunk.readOpcode(frame.pc);
        frame.pc += 1;

        switch (op) {
            .LoadConst => {
                const idx = frame.chunk.readByte(frame.pc);
                frame.pc += 1;
                try self.pushF64(frame.chunk.constants[idx].number);
            },
            .LoadTrue => try self.pushBool(true),
            .LoadFalse => try self.pushBool(false),

            .LoadLocalF64 => {
                const slot = frame.chunk.readU32(frame.pc);
                frame.pc += 4;
                try self.pushF64(frame.locals[slot].number);
            },
            .LoadLocalBool => {
                const slot = frame.chunk.readU32(frame.pc);
                frame.pc += 4;
                try self.pushBool(frame.locals[slot].boolean);
            },
            .StoreLocalF64 => {
                const slot = frame.chunk.readU32(frame.pc);
                frame.pc += 4;
                frame.locals[slot] = .{ .number = self.popF64() };
            },
            .StoreLocalBool => {
                const slot = frame.chunk.readU32(frame.pc);
                frame.pc += 4;
                frame.locals[slot] = .{ .boolean = self.popBool() };
            },

            .OP_CALL => {
                const fn_idx = frame.chunk.readU32(frame.pc);
                frame.pc += 4;
                const func = &self.program.functions[fn_idx];
                try self.frames.push(&func.chunk, func.locals_count);
                const new_frame = self.frames.current();
                var i: usize = func.param_kinds.len;
                while (i > 0) {
                    i -= 1;
                    switch (func.param_kinds[i]) {
                        .F64 => new_frame.locals[i] = .{ .number = self.popF64() },
                        .Bool => new_frame.locals[i] = .{ .boolean = self.popBool() },
                        .Void => unreachable,
                    }
                }
            },

            .Add => {
                const b = self.popF64();
                const a = self.popF64();
                try self.pushF64(a + b);
            },
            .Sub => {
                const b = self.popF64();
                const a = self.popF64();
                try self.pushF64(a - b);
            },
            .Mul => {
                const b = self.popF64();
                const a = self.popF64();
                try self.pushF64(a * b);
            },
            .Div => {
                const b = self.popF64();
                const a = self.popF64();
                try self.pushF64(a / b);
            },

            .Lt => {
                const b = self.popF64();
                const a = self.popF64();
                try self.pushBool(a < b);
            },
            .Lte => {
                const b = self.popF64();
                const a = self.popF64();
                try self.pushBool(a <= b);
            },
            .Gt => {
                const b = self.popF64();
                const a = self.popF64();
                try self.pushBool(a > b);
            },
            .Gte => {
                const b = self.popF64();
                const a = self.popF64();
                try self.pushBool(a >= b);
            },

            .EqF64 => {
                const b = self.popF64();
                const a = self.popF64();
                try self.pushBool(a == b);
            },
            .EqBool => {
                const b = self.popBool();
                const a = self.popBool();
                try self.pushBool(a == b);
            },
            .NeqF64 => {
                const b = self.popF64();
                const a = self.popF64();
                try self.pushBool(a != b);
            },
            .NeqBool => {
                const b = self.popBool();
                const a = self.popBool();
                try self.pushBool(a != b);
            },

            .Neg => try self.pushF64(-self.popF64()),
            .Not => try self.pushBool(!self.popBool()),

            .Jump => {
                const offset = frame.chunk.readU16(frame.pc);
                frame.pc += 2;
                frame.pc += offset;
            },
            .JumpIfFalse => {
                const offset = frame.chunk.readU16(frame.pc);
                frame.pc += 2;
                if (!self.popBool()) frame.pc += offset;
            },
            .Loop => {
                const offset = frame.chunk.readU16(frame.pc);
                frame.pc += 2;
                frame.pc -= offset;
            },

            .ReturnF64 => {
                const v = self.popF64();
                if (self.frames.count == 1) return .{ .F64 = v };
                self.frames.pop();
                try self.pushF64(v);
            },
            .ReturnBool => {
                const v = self.popBool();
                if (self.frames.count == 1) return .{ .Bool = v };
                self.frames.pop();
                try self.pushBool(v);
            },
            .ReturnVoid => {
                if (self.frames.count == 1) return .Void;
                self.frames.pop();
            },
        }
    }
}

fn pushF64(self: *Self, v: f64) !void {
    if (self.sp + 8 > self.stack.len) return error.StackOverflow;
    std.mem.writeInt(u64, self.stack[self.sp..][0..8], @bitCast(v), .little);
    self.sp += 8;
}

fn popF64(self: *Self) f64 {
    self.sp -= 8;
    return @bitCast(std.mem.readInt(u64, self.stack[self.sp..][0..8], .little));
}

fn pushBool(self: *Self, v: bool) !void {
    if (self.sp + 1 > self.stack.len) return error.StackOverflow;
    self.stack[self.sp] = @intFromBool(v);
    self.sp += 1;
}

fn popBool(self: *Self) bool {
    self.sp -= 1;
    return self.stack[self.sp] != 0;
}
