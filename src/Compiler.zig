const std = @import("std");

const Bytecode = @import("Bytecode.zig");
const Debug = @import("DebugLogger.zig");
const Ast = @import("Structures/Ast.zig");
const Value = @import("Structures/Ast/Value.zig").Value;
const ConstantStore = @import("Structures/ConstantStore.zig");
const CompilerState = @import("CompilerState.zig");
const Program = @import("Program.zig");
const Self = @This();

pub const Error = error{
    UnresolvedDeclaration,
    UnresolvedAssignment,
    UnresolvedIdentifier,
} || ConstantStore.Error;

code: std.ArrayList(u8),
constants: ConstantStore,
state: CompilerState,
functions: std.ArrayList(Program.Function),
pub fn init() Self {
    return .{
        .code = .empty,
        .constants = ConstantStore.init(),
        .state = .init(),
        .functions = .empty,
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.code.deinit(allocator);
    self.constants.deinit(allocator);
    for (self.functions.items) |*func| {
        func.deinit(allocator);
    }
    self.functions.deinit(allocator);
}
pub fn compileProgram(self: *Self, allocator: std.mem.Allocator, ast: Ast.Block) Error!Program {
    var program = Program.init();
    errdefer program.deinit(allocator);
    const main = try self.compileBytecode(allocator, ast);
    program.main = main;
    program.functions = try self.functions.toOwnedSlice(allocator);
    return program;
}
pub fn compileBytecode(self: *Self, allocator: std.mem.Allocator, ast: Ast.Block) Error!Bytecode {
    for (ast.statements) |statement| {
        try self.compileStatement(allocator, statement);
    }
    if (!self.state.has_return) {
        const idx = try self.constants.add(allocator, .{ .number = 0 });
        try self.emitFromOpCode(allocator, .LoadConst);
        try self.emitByte(allocator, idx);
        try self.emitFromOpCode(allocator, .Return);
    }
    const main = Bytecode{
        .code = try self.code.toOwnedSlice(allocator),
        .constants = try self.constants.toOwnedSlice(allocator),
    };
    return main;
}

fn compileStatement(self: *Self, allocator: std.mem.Allocator, statement: *Ast.Statement) Error!void {
    switch (statement.*) {
        .var_dclr => try self.compileVarDeclr(allocator, statement),
        .assign_stmt => try self.compileAssign(allocator, statement),
        .expression_stmt => try self.compileExpression(allocator, statement.expression_stmt),
        .if_stmt => try self.compileIfStmt(allocator, statement),
        .while_stmt => try self.compileWhile(allocator, statement),
        .return_stmt => try self.compileReturnStmt(allocator, statement),
        .fn_stmt => try self.compileFn(allocator, statement),
    }
}

fn compileVarDeclr(self: *Self, allocator: std.mem.Allocator, statement: *Ast.Statement) Error!void {
    const var_dclr = statement.var_dclr;
    try self.compileExpression(allocator, var_dclr.value);
    const slot = var_dclr.slot orelse return Error.UnresolvedDeclaration;
    try self.emitFromOpCode(allocator, .StoreLocal);
    try self.emitU32(allocator, slot);
}

fn compileAssign(self: *Self, allocator: std.mem.Allocator, statement: *Ast.Statement) Error!void {
    const assign = statement.assign_stmt;
    try self.compileExpression(allocator, assign.value);
    const slot = assign.slot orelse return Error.UnresolvedAssignment;
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
fn compileReturnStmt(self: *Self, allocator: std.mem.Allocator, statement: *Ast.Statement) !void {
    const ret = statement.return_stmt;
    if (ret.value) |v| {
        try self.compileExpression(allocator, v);
    }
    try self.emitFromOpCode(allocator, .Return);
    self.state.has_return = true;
}
fn compileFn(self: *Self, allocator: std.mem.Allocator, statement: *Ast.Statement) !void {
    const fn_stmt = statement.fn_stmt;
    var sub_compiler = Self.init();
    errdefer sub_compiler.deinit(allocator);
    var sub_bytecode = try sub_compiler.compileBytecode(allocator, fn_stmt.body);
    errdefer sub_bytecode.deinit(allocator);
    const locals_count = fn_stmt.locals_count orelse unreachable;
    var function = Program.Function.init(sub_bytecode, @intCast(fn_stmt.params.len), locals_count);
    errdefer function.deinit(allocator);
    try self.functions.append(allocator, function);
}
fn emitLoop(self: *Self, allocator: std.mem.Allocator, loop_start: usize) Error!void {
    try self.emitFromOpCode(allocator, .Loop);
    const after = self.code.items.len + 2;
    const offset: u16 = @intCast(after - loop_start);
    try self.emitU16(allocator, offset);
}

fn compileBlock(self: *Self, allocator: std.mem.Allocator, block: Ast.Block) Error!void {
    for (block.statements) |statement| {
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
            const slot = ident.slot orelse return Error.UnresolvedIdentifier;
            try self.emitFromOpCode(allocator, .LoadLocal);
            try self.emitU32(allocator, slot);
        },

        .binary => |b| {
            try self.compileExpression(allocator, b.left);
            try self.compileExpression(allocator, b.right);
            const op: Bytecode.Opcode = switch (b.op) {
                .Add => .Add,
                .Sub => .Sub,
                .Mul => .Mul,
                .Div => .Div,
                .Eq => .Eq,
                .Neq => .Neq,
                .Lt => .Lt,
                .Lte => .Lte,
                .Gt => .Gt,
                .Gte => .Gte,
            };
            try self.emitFromOpCode(allocator, op);
        },
        .unary => |u| {
            try self.compileExpression(allocator, u.operand);
            const op: Bytecode.Opcode = switch (u.op) {
                .Negate => .Neg,
            };
            try self.emitFromOpCode(allocator, op);
        },
        .grouping => |inner| {
            try self.compileExpression(allocator, inner);
        },

        .call => |c| {
            for (c.args) |arg| {
                try self.compileExpression(allocator, arg);
            }
            _ = try self.emitFromOpCode(allocator, .OP_CALL);
            try self.emitU32(allocator, c.fn_idx orelse unreachable);
            try self.emitByte(allocator, @intCast(c.args.len));
        },
    }
}
