const std = @import("std");

const Bytecode = @import("Structures/Bytecode.zig");
const Debug = @import("Compiler/DebugLogger.zig");
const Ast = @import("Structures/Ast.zig");
const Value = @import("Structures/Ast/Value.zig").Value;
const ConstantStore = @import("Structures/ConstantStore.zig");
const CompilerState = @import("Compiler/State.zig");
const Program = @import("Structures/Program.zig");
const ZType = @import("Structures/Ast/ZType.zig");
const Self = @This();

pub const Error = error{
    UnresolvedDeclaration,
    UnresolvedAssignment,
    UnresolvedIdentifier,
    UnresolvedCall,
    UnsupportedType,
} || ConstantStore.Error;

const FnSig = struct {
    param_kinds: []Bytecode.PrimKind,
    return_kind: Bytecode.PrimKind,
};

const FnSigTable = std.AutoHashMapUnmanaged(u32, FnSig);

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
    self.state.deinit(allocator);
    for (self.functions.items) |*func| {
        func.deinit(allocator);
    }
    self.functions.deinit(allocator);
}

pub fn compileProgram(self: *Self, allocator: std.mem.Allocator, ast: Ast.Block) Error!Program {
    var signatures: FnSigTable = .empty;
    defer {
        var it = signatures.valueIterator();
        while (it.next()) |sig| allocator.free(sig.param_kinds);
        signatures.deinit(allocator);
    }
    try collectSignatures(allocator, ast, &signatures);

    var program = Program.init();
    errdefer program.deinit(allocator);
    self.state.current_return_kind = .F64;
    const main = try self.compileBytecode(allocator, ast, &signatures);
    program.main = main;
    program.functions = try self.functions.toOwnedSlice(allocator);
    return program;
}

fn collectSignatures(
    allocator: std.mem.Allocator,
    ast: Ast.Block,
    sigs: *FnSigTable,
) Error!void {
    for (ast.statements) |statement| {
        if (statement.* != .fn_stmt) continue;
        const fn_stmt = &statement.fn_stmt;
        const fn_idx = fn_stmt.fn_idx orelse return Error.UnresolvedCall;
        const param_kinds = try allocator.alloc(Bytecode.PrimKind, fn_stmt.params.len);
        for (fn_stmt.params, 0..) |p, i| {
            param_kinds[i] = kindFromZType(p.param_type.resolved.?);
        }
        const return_kind = if (fn_stmt.return_type.resolved) |k| kindFromZType(k) else .Void;
        try sigs.put(allocator, fn_idx, .{
            .param_kinds = param_kinds,
            .return_kind = return_kind,
        });
    }
}

fn kindFromZType(kind: ZType.Kind) Bytecode.PrimKind {
    return switch (kind) {
        .numeric => .F64,
        .Bool => .Bool,
        else => @panic("unsupported runtime type"),
    };
}

pub fn compileBytecode(
    self: *Self,
    allocator: std.mem.Allocator,
    ast: Ast.Block,
    sigs: *const FnSigTable,
) Error!Bytecode {
    for (ast.statements) |statement| {
        try self.compileStatement(allocator, statement, sigs);
    }
    if (!self.state.has_return) {
        switch (self.state.current_return_kind) {
            .F64 => {
                const idx = try self.constants.add(allocator, .{ .number = 0 });
                try self.emitFromOpCode(allocator, .LoadConst);
                try self.emitByte(allocator, idx);
                try self.emitFromOpCode(allocator, .ReturnF64);
            },
            .Bool => {
                try self.emitFromOpCode(allocator, .LoadFalse);
                try self.emitFromOpCode(allocator, .ReturnBool);
            },
            .Void => {
                try self.emitFromOpCode(allocator, .ReturnVoid);
            },
        }
    }
    return .{
        .code = try self.code.toOwnedSlice(allocator),
        .constants = try self.constants.toOwnedSlice(allocator),
    };
}

fn compileStatement(
    self: *Self,
    allocator: std.mem.Allocator,
    statement: *Ast.Statement,
    sigs: *const FnSigTable,
) Error!void {
    switch (statement.*) {
        .var_dclr => try self.compileVarDeclr(allocator, statement, sigs),
        .assign_stmt => try self.compileAssign(allocator, statement, sigs),
        .expression_stmt => try self.compileExpression(allocator, statement.expression_stmt, sigs),
        .if_stmt => try self.compileIfStmt(allocator, statement, sigs),
        .while_stmt => try self.compileWhile(allocator, statement, sigs),
        .return_stmt => try self.compileReturnStmt(allocator, statement, sigs),
        .fn_stmt => try self.compileFn(allocator, statement, sigs),
    }
}

fn compileVarDeclr(
    self: *Self,
    allocator: std.mem.Allocator,
    statement: *Ast.Statement,
    sigs: *const FnSigTable,
) Error!void {
    const var_dclr = statement.var_dclr;
    try self.compileExpression(allocator, var_dclr.value, sigs);
    const slot = var_dclr.slot orelse return Error.UnresolvedDeclaration;
    const kind = kindFromZType(var_dclr.type.resolved.?);
    try self.state.slot_types.put(allocator, slot, kind);
    try self.emitStoreLocal(allocator, kind, slot);
}

fn compileAssign(
    self: *Self,
    allocator: std.mem.Allocator,
    statement: *Ast.Statement,
    sigs: *const FnSigTable,
) Error!void {
    const assign = statement.assign_stmt;
    try self.compileExpression(allocator, assign.value, sigs);
    const slot = assign.slot orelse return Error.UnresolvedAssignment;
    const kind = self.state.slot_types.get(slot) orelse return Error.UnresolvedAssignment;
    try self.emitStoreLocal(allocator, kind, slot);
}

fn emitStoreLocal(self: *Self, allocator: std.mem.Allocator, kind: Bytecode.PrimKind, slot: u32) Error!void {
    const op: Bytecode.Opcode = switch (kind) {
        .F64 => .StoreLocalF64,
        .Bool => .StoreLocalBool,
        .Void => return Error.UnsupportedType,
    };
    try self.emitFromOpCode(allocator, op);
    try self.emitU32(allocator, slot);
}

fn compileIfStmt(
    self: *Self,
    allocator: std.mem.Allocator,
    statement: *Ast.Statement,
    sigs: *const FnSigTable,
) Error!void {
    const if_stmt = statement.if_stmt;
    try self.compileExpression(allocator, if_stmt.condition, sigs);

    const then_jump = try self.emitJump(allocator, .JumpIfFalse);
    try self.compileBlock(allocator, if_stmt.then_branch, sigs);

    if (if_stmt.else_branch) |else_branch| {
        const else_jump = try self.emitJump(allocator, .Jump);
        self.patchJump(then_jump);
        try self.compileBlock(allocator, else_branch, sigs);
        self.patchJump(else_jump);
    } else {
        self.patchJump(then_jump);
    }
}

fn compileWhile(
    self: *Self,
    allocator: std.mem.Allocator,
    statement: *Ast.Statement,
    sigs: *const FnSigTable,
) Error!void {
    const while_stmt = statement.while_stmt;
    const loop_start = self.code.items.len;
    try self.compileExpression(allocator, while_stmt.condition, sigs);
    const exit_jump = try self.emitJump(allocator, .JumpIfFalse);
    try self.compileBlock(allocator, while_stmt.then_branch, sigs);
    try self.emitLoop(allocator, loop_start);
    self.patchJump(exit_jump);
}

fn compileReturnStmt(
    self: *Self,
    allocator: std.mem.Allocator,
    statement: *Ast.Statement,
    sigs: *const FnSigTable,
) Error!void {
    const ret = statement.return_stmt;
    if (ret.value) |v| {
        try self.compileExpression(allocator, v, sigs);
        switch (self.state.current_return_kind) {
            .F64 => try self.emitFromOpCode(allocator, .ReturnF64),
            .Bool => try self.emitFromOpCode(allocator, .ReturnBool),
            .Void => return Error.UnsupportedType,
        }
    } else {
        try self.emitFromOpCode(allocator, .ReturnVoid);
    }
    self.state.has_return = true;
}

fn compileFn(
    self: *Self,
    allocator: std.mem.Allocator,
    statement: *Ast.Statement,
    sigs: *const FnSigTable,
) Error!void {
    const fn_stmt = statement.fn_stmt;
    const fn_idx = fn_stmt.fn_idx orelse return Error.UnresolvedCall;
    const sig = sigs.get(fn_idx) orelse return Error.UnresolvedCall;

    var sub_compiler = Self.init();
    defer sub_compiler.deinit(allocator);

    for (fn_stmt.params, 0..) |p, i| {
        const param_slot = p.slot orelse return Error.UnresolvedDeclaration;
        try sub_compiler.state.slot_types.put(allocator, param_slot, sig.param_kinds[i]);
    }
    sub_compiler.state.current_return_kind = sig.return_kind;

    var sub_bytecode = try sub_compiler.compileBytecode(allocator, fn_stmt.body, sigs);
    errdefer sub_bytecode.deinit(allocator);

    const locals_count = fn_stmt.locals_count orelse unreachable;

    const owned_param_kinds = try allocator.dupe(Bytecode.PrimKind, sig.param_kinds);
    errdefer allocator.free(owned_param_kinds);

    const function = Program.Function.init(
        sub_bytecode,
        @intCast(fn_stmt.params.len),
        locals_count,
        owned_param_kinds,
        sig.return_kind,
    );

    try self.functions.append(allocator, function);
}

fn emitLoop(self: *Self, allocator: std.mem.Allocator, loop_start: usize) Error!void {
    try self.emitFromOpCode(allocator, .Loop);
    const after = self.code.items.len + 2;
    const offset: u16 = @intCast(after - loop_start);
    try self.emitU16(allocator, offset);
}

fn compileBlock(
    self: *Self,
    allocator: std.mem.Allocator,
    block: Ast.Block,
    sigs: *const FnSigTable,
) Error!void {
    for (block.statements) |statement| {
        try self.compileStatement(allocator, statement, sigs);
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

fn compileExpression(
    self: *Self,
    allocator: std.mem.Allocator,
    expr: *Ast.Expression,
    sigs: *const FnSigTable,
) Error!void {
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
            const kind = self.state.slot_types.get(slot) orelse return Error.UnresolvedIdentifier;
            const op: Bytecode.Opcode = switch (kind) {
                .F64 => .LoadLocalF64,
                .Bool => .LoadLocalBool,
                .Void => return Error.UnsupportedType,
            };
            try self.emitFromOpCode(allocator, op);
            try self.emitU32(allocator, slot);
        },

        .binary => |b| {
            try self.compileExpression(allocator, b.left, sigs);
            try self.compileExpression(allocator, b.right, sigs);
            const op: Bytecode.Opcode = switch (b.op) {
                .Add => .Add,
                .Sub => .Sub,
                .Mul => .Mul,
                .Div => .Div,
                .Lt => .Lt,
                .Lte => .Lte,
                .Gt => .Gt,
                .Gte => .Gte,
                .Eq => switch (try self.exprKind(b.left, sigs)) {
                    .F64 => .EqF64,
                    .Bool => .EqBool,
                    .Void => return Error.UnsupportedType,
                },
                .Neq => switch (try self.exprKind(b.left, sigs)) {
                    .F64 => .NeqF64,
                    .Bool => .NeqBool,
                    .Void => return Error.UnsupportedType,
                },
            };
            try self.emitFromOpCode(allocator, op);
        },
        .unary => |u| {
            try self.compileExpression(allocator, u.operand, sigs);
            const op: Bytecode.Opcode = switch (u.op) {
                .Negate => .Neg,
            };
            try self.emitFromOpCode(allocator, op);
        },
        .grouping => |inner| {
            try self.compileExpression(allocator, inner, sigs);
        },

        .call => |c| {
            for (c.args) |arg| {
                try self.compileExpression(allocator, arg, sigs);
            }
            try self.emitFromOpCode(allocator, .OP_CALL);
            try self.emitU32(allocator, c.fn_idx orelse return Error.UnresolvedCall);
        },
    }
}

fn exprKind(self: *Self, expr: *Ast.Expression, sigs: *const FnSigTable) Error!Bytecode.PrimKind {
    return switch (expr.*) {
        .literal => |v| switch (v) {
            .number => .F64,
            .boolean => .Bool,
            else => Error.UnsupportedType,
        },
        .binary => |b| switch (b.op) {
            .Add, .Sub, .Mul, .Div => .F64,
            .Lt, .Lte, .Gt, .Gte, .Eq, .Neq => .Bool,
        },
        .unary => |u| switch (u.op) {
            .Negate => .F64,
        },
        .grouping => |inner| self.exprKind(inner, sigs),
        .identifier => |id| blk: {
            const slot = id.slot orelse return Error.UnresolvedIdentifier;
            break :blk self.state.slot_types.get(slot) orelse Error.UnresolvedIdentifier;
        },
        .call => |c| blk: {
            const fn_idx = c.fn_idx orelse return Error.UnresolvedCall;
            const sig = sigs.get(fn_idx) orelse return Error.UnresolvedCall;
            break :blk sig.return_kind;
        },
    };
}
