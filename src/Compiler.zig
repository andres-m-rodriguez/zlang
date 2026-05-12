const std = @import("std");
const Value = @import("Structures/Ast/Value.zig").Value;
const ConstantStore = @import("Structures/ConstantStore.zig");
const Bytecode = @import("Bytecode.zig");
const Ast = @import("Structures/Ast.zig");
const Self = @This();

pub const Error = error{
    UnresolvedDeclaration,
    UnresolvedAssignment,
    UnresolvedIdentifier,
    TooManyConstants,
} || std.mem.Allocator.Error;

code: std.ArrayList(u8),
constants: ConstantStore,

pub fn init() Self {
    return .{
        .code = .empty,
        .constants = ConstantStore.init(),
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.code.deinit(allocator);
    self.constants.deinit(allocator);
}

pub fn compile(self: *Self, allocator: std.mem.Allocator, ast: []*Ast.Statement) Error!Bytecode {
    for (ast) |statement| {
        try self.compileStatement(allocator, statement);
    }
    return .{
        .code = try self.code.toOwnedSlice(allocator),
        .constants = try self.constants.toOwnedSlice(allocator),
    };
}

fn compileStatement(self: *Self, allocator: std.mem.Allocator, statement: *Ast.Statement) Error!void {
    switch (statement.*) {
        .var_dclr => try self.compileVarDeclr(allocator, statement),
        .assign => try self.compileAssign(allocator, statement),
        .expression => try self.compileExpression(allocator, statement.expression),
        .if_stmt => try self.compileIfStmt(allocator, statement),
        .while_stmt => try self.compileWhile(allocator, statement),
    }
}

fn compileVarDeclr(self: *Self, allocator: std.mem.Allocator, statement: *Ast.Statement) Error!void {
    const var_dclr = statement.var_dclr;
    try self.compileExpression(allocator, var_dclr.value);
    const slot = var_dclr.slot orelse return error.UnresolvedDeclaration;
    try self.emitFromOpCode(allocator, .StoreLocal);
    try self.emitU32(allocator, slot);
}

fn compileAssign(self: *Self, allocator: std.mem.Allocator, statement: *Ast.Statement) Error!void {
    const assign = statement.assign;
    try self.compileExpression(allocator, assign.value);
    const slot = assign.slot orelse return error.UnresolvedAssignment;
    try self.emitFromOpCode(allocator, .StoreLocal);
    try self.emitU32(allocator, slot);
}

fn compileIfStmt(self: *Self, allocator: std.mem.Allocator, statement: *Ast.Statement) Error!void {
    const if_stmt = statement.if_stmt;
    try self.compileExpression(allocator, if_stmt.condition);

    const then_jump = try self.emitJump(allocator, .JumpIfFalse);
    try self.compileBlock(allocator, if_stmt.then_branch);

    if (if_stmt.else_branch) |else_branch| {
        const else_jump = try self.emitJump(allocator, .Jump);
        self.patchJump(then_jump);
        try self.compileBlock(allocator, else_branch);
        self.patchJump(else_jump);
    } else {
        self.patchJump(then_jump);
    }
}

fn compileWhile(self: *Self, allocator: std.mem.Allocator, statement: *Ast.Statement) Error!void {
    const while_stmt = statement.while_stmt;
    const loop_start = self.code.items.len;
    try self.compileExpression(allocator, while_stmt.condition);
    const exit_jump = try self.emitJump(allocator, .JumpIfFalse);
    try self.compileBlock(allocator, while_stmt.then_branch);
    try self.emitLoop(allocator, loop_start);
    self.patchJump(exit_jump);
}

fn emitLoop(self: *Self, allocator: std.mem.Allocator, loop_start: usize) Error!void {
    try self.emitFromOpCode(allocator, .Loop);
    const after = self.code.items.len + 2;
    const offset: u16 = @intCast(after - loop_start);
    try self.emitU16(allocator, offset);
}

fn compileBlock(self: *Self, allocator: std.mem.Allocator, block: []*Ast.Statement) Error!void {
    for (block) |statement| {
        try self.compileStatement(allocator, statement);
    }
}

fn emitByte(self: *Self, allocator: std.mem.Allocator, byte: u8) Error!void {
    try self.code.append(allocator, byte);
}

fn emitFromOpCode(self: *Self, allocator: std.mem.Allocator, op_code: Bytecode.Opcode) Error!void {
    return self.emitByte(allocator, @intFromEnum(op_code));
}

fn emitU16(self: *Self, allocator: std.mem.Allocator, value: u16) Error!void {
    var buf: [2]u8 = undefined;
    std.mem.writeInt(u16, &buf, value, .little);
    try self.code.appendSlice(allocator, &buf);
}

fn emitU32(self: *Self, allocator: std.mem.Allocator, value: u32) Error!void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, value, .little);
    try self.code.appendSlice(allocator, &buf);
}

fn emitJump(self: *Self, allocator: std.mem.Allocator, op: Bytecode.Opcode) Error!usize {
    try self.emitFromOpCode(allocator, op);
    const placeholder_addr = self.code.items.len;
    try self.emitU16(allocator, 0xFFFF);
    return placeholder_addr;
}

fn patchJump(self: *Self, placeholder_addr: usize) void {
    const target = self.code.items.len;
    const offset: u16 = @intCast(target - placeholder_addr - 2);
    std.mem.writeInt(u16, self.code.items[placeholder_addr..][0..2], offset, .little);
}

fn compileExpression(self: *Self, allocator: std.mem.Allocator, expr: *Ast.Expression) Error!void {
    switch (expr.*) {
        .literal => |value| {
            switch (value) {
                .boolean => |b| {
                    const op: Bytecode.Opcode = if (b) .LoadTrue else .LoadFalse;
                    try self.emitFromOpCode(allocator, op);
                },
                else => {
                    const idx = try self.constants.add(allocator, value);
                    try self.emitFromOpCode(allocator, .LoadConst);
                    try self.emitByte(allocator, idx);
                },
            }
        },

        .identifier => |ident| {
            const slot = ident.slot orelse return error.UnresolvedIdentifier;
            try self.emitFromOpCode(allocator, .LoadLocal);
            try self.emitU32(allocator, slot);
        },

        .binary => |b| {
            try self.compileExpression(allocator, b.left);
            try self.compileExpression(allocator, b.right);
            const op: Bytecode.Opcode = switch (b.op) {
                .add => .Add,
                .sub => .Sub,
                .mul => .Mul,
                .div => .Div,
                .eq => .Eq,
                .neq => .Neq,
                .lt => .Lt,
                .lte => .Lte,
                .gt => .Gt,
                .gte => .Gte,
            };
            try self.emitFromOpCode(allocator, op);
        },

        .unary => |u| {
            try self.compileExpression(allocator, u.operand);
            const op: Bytecode.Opcode = switch (u.op) {
                .negate => .Neg,
            };
            try self.emitFromOpCode(allocator, op);
        },

        .grouping => |inner| {
            try self.compileExpression(allocator, inner);
        },
    }
}
