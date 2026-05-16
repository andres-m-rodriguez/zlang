const std = @import("std");
const Value = @import("Structures/Ast.zig").Value;
const Bytecode = @import("Bytecode.zig");
const Program = @import("Program.zig");
const FrameStore = @import("FrameStore.zig");
const Self = @This();

stack: []Value,
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
        .stack = try allocator.alloc(Value, stack_size),
        .sp = 0,
        .frames = try FrameStore.init(allocator, max_frames, locals_pool_size),
        .program = program,
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.free(self.stack);
    self.frames.deinit(allocator);
}

pub fn run(self: *Self, main_locals_count: u16) !?Value {
    try self.frames.push(&self.program.main, main_locals_count);

    while (true) {
        const frame = self.frames.current();
        const op = frame.chunk.readOpcode(frame.pc);
        frame.pc += 1;

        switch (op) {
            .LoadConst => {
                const idx = frame.chunk.readByte(frame.pc);
                frame.pc += 1;
                try self.push(frame.chunk.constants[idx]);
            },
            .LoadTrue => {
                try self.push(.{ .boolean = true });
            },
            .LoadFalse => {
                try self.push(.{ .boolean = false });
            },
            .LoadLocal => {
                const slot = frame.chunk.readU32(frame.pc);
                frame.pc += 4;
                try self.push(frame.locals[slot]);
            },
            .StoreLocal => {
                const slot = frame.chunk.readU32(frame.pc);
                frame.pc += 4;
                frame.locals[slot] = self.pop();
            },
            .Pop => {
                _ = self.pop();
            },
            .OP_CALL => {
                const func_idx = frame.chunk.readU32(frame.pc);
                frame.pc += 4;
                const func_args = frame.chunk.readByte(frame.pc);
                frame.pc += 1;

                const func = &self.program.functions[func_idx];
                try self.frames.push(&func.chunk, func.locals_count);
                const new_frame = self.frames.current();
                var i: usize = func_args;
                while (i > 0) : (i -= 1) {
                    new_frame.locals[i - 1] = self.pop();
                }
            },
            .Add => {
                const b = self.pop();
                const a = self.pop();
                try self.push(.{ .number = a.number + b.number });
            },
            .Sub => {
                const b = self.pop();
                const a = self.pop();
                try self.push(.{ .number = a.number - b.number });
            },
            .Mul => {
                const b = self.pop();
                const a = self.pop();
                try self.push(.{ .number = a.number * b.number });
            },
            .Div => {
                const b = self.pop();
                const a = self.pop();
                try self.push(.{ .number = a.number / b.number });
            },
            .Lt => {
                const b = self.pop();
                const a = self.pop();
                try self.push(.{ .boolean = a.number < b.number });
            },
            .Lte => {
                const b = self.pop();
                const a = self.pop();
                try self.push(.{ .boolean = a.number <= b.number });
            },
            .Gt => {
                const b = self.pop();
                const a = self.pop();
                try self.push(.{ .boolean = a.number > b.number });
            },
            .Gte => {
                const b = self.pop();
                const a = self.pop();
                try self.push(.{ .boolean = a.number >= b.number });
            },
            .Eq => {
                const b = self.pop();
                const a = self.pop();
                try self.push(.{ .boolean = a.number == b.number });
            },
            .Neq => {
                const b = self.pop();
                const a = self.pop();
                try self.push(.{ .boolean = a.number != b.number });
            },
            .Neg => {
                const v = self.pop();
                try self.push(.{ .number = -v.number });
            },
            .Not => {
                const v = self.pop();
                try self.push(.{ .boolean = !v.boolean });
            },
            .Jump => {
                const offset = frame.chunk.readU16(frame.pc);
                frame.pc += 2;
                frame.pc += offset;
            },
            .JumpIfFalse => {
                const offset = frame.chunk.readU16(frame.pc);
                frame.pc += 2;
                const cond = self.pop();
                if (!cond.boolean) frame.pc += offset;
            },
            .Loop => {
                const offset = frame.chunk.readU16(frame.pc);
                frame.pc += 2;
                frame.pc -= offset;
            },
            .Return => {
                const ret_val: ?Value = if (self.sp > 0) self.pop() else null;
                if (self.frames.count == 1) return ret_val; 
                self.frames.pop();
                if (ret_val) |v| try self.push(v);
            },
        }
    }
}

fn push(self: *Self, value: Value) !void {
    if (self.sp >= self.stack.len) return error.StackOverflow;
    self.stack[self.sp] = value;
    self.sp += 1;
}

fn pop(self: *Self) Value {
    self.sp -= 1;
    return self.stack[self.sp];
}
