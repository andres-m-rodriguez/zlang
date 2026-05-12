const std = @import("std");
const Value = @import("Structures/Ast.zig").Value;
const Bytecode = @import("Bytecode.zig");
const Self = @This();

// Allocator is not stored, we pass it explicitly to init and deinit.
// To match the unmanaged convention used throughout the codebase.
stack: []Value,
sp: usize,
locals: []Value,
constants: []const Value,
pc: usize,

pub fn init(allocator: std.mem.Allocator, stack_size: usize, locals_size: usize, constants: []const Value) !Self {
    return .{
        .stack = try allocator.alloc(Value, stack_size),
        .sp = 0,
        .locals = try allocator.alloc(Value, locals_size),
        .constants = constants,
        .pc = 0,
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.free(self.stack);
    allocator.free(self.locals);
}

pub fn run(self: *Self, bytecode: Bytecode) !?Value {
    while (true) {
        const op = bytecode.readOpcode(self.pc);
        self.pc += 1;
        switch (op) {
            .LoadConst => {
                const idx = bytecode.readByte(self.pc);
                self.advance(.LoadConst);
                try self.push(bytecode.constants[idx]);
            },
            .LoadTrue => {
                try self.push(.{ .boolean = true });
            },
            .LoadFalse => {
                try self.push(.{ .boolean = false });
            },
            .LoadLocal => {
                const slot = bytecode.readU32(self.pc);
                self.advance(.LoadLocal);
                try self.push(self.locals[slot]);
            },
            .StoreLocal => {
                const slot = bytecode.readU32(self.pc);
                self.advance(.StoreLocal);
                self.locals[slot] = self.pop();
            },
            .Pop => {
                _ = self.pop();
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
                const offset = bytecode.readU16(self.pc);
                self.advance(.Jump);
                self.pc += offset;
            },
            .JumpIfFalse => {
                const offset = bytecode.readU16(self.pc);
                self.advance(.JumpIfFalse);
                const cond = self.pop();
                if (!cond.boolean) self.pc += offset;
            },
            .Loop => {
                const offset = bytecode.readU16(self.pc);
                self.advance(.Loop);
                self.pc -= offset;
            },
            .Return => {
                if (self.sp > 0) return self.pop();
                return null;
            },
        }
    }
}

fn advance(self: *Self, op: Bytecode.Opcode) void {
    self.pc += Bytecode.operandSize(op);
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
