const std = @import("std");
const Lexer = @import("Lexer.zig");
const Ast = @import("Structures/Ast.zig");
const Parser = @import("Parser.zig");
const Resolver = @import("Resolver.zig");
const TypeChecker = @import("TypeChecker.zig");
const Compiler = @import("Compiler.zig");
const Bytecode = @import("Structures/Bytecode.zig");
const Program = @import("Structures/Program.zig");
const VirtualMachine = @import("VirtualMachine.zig");
const Config = @import("Config.zig");
const Z = @import("Z");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    var c_buffer: [4096]u8 = undefined;
    var c_writer = std.Io.File.stdout().writer(init.io, &c_buffer);
    const writer = &c_writer.interface;
    const source = @embedFile("./Index.txt");
    var cfg = Config.init();
    try cfg.parse(source);
    var lex = Lexer.init(source);
    var parser = Parser.init(&lex);
    const ast = try parser.parse(allocator);
    defer ast.deinit(allocator);
    var type_checker = TypeChecker.init();
    defer type_checker.deinit(allocator);
    try type_checker.check(allocator, ast);
    var resolver = Resolver.init();
    defer resolver.deinit(allocator);
    try resolver.resolve(allocator, ast);
    var compiler = Compiler.init();
    defer compiler.deinit(allocator);
    var program = try compiler.compileProgram(allocator, ast);
    defer program.deinit(allocator);
    try dumpProgram(writer, &program);
    try writer.writeAll("=== running ===\n");
    try writer.flush();

    const main_locals: u16 = @intCast(resolver.maxSlots());
    const max_frames: usize = 256;
    var virtual_machine = try VirtualMachine.init(
        allocator,
        cfg.stack_size,
        max_frames,
        computeLocalsPoolSize(&program, main_locals, max_frames),
        &program,
    );
    defer virtual_machine.deinit(allocator);
    const result = try virtual_machine.run(main_locals);
    try writer.writeAll("=== main locals after run ===\n");
    const main_frame = &virtual_machine.frames.frames[0];
    for (main_frame.locals, 0..) |value, i| {
        try writer.print("  [{d}] {any}\n", .{ i, value });
    }
    try writer.writeAll("=== result ===\n");
    switch (result) {
        .F64 => |v| try writer.print("  {d}\n", .{v}),
        .Bool => |b| try writer.print("  {}\n", .{b}),
        .Void => try writer.writeAll("  (void)\n"),
    }
    try writer.flush();
}

fn dumpProgram(writer: *std.Io.Writer, program: *const Program) !void {
    try writer.writeAll("=== main ===\n");
    try dumpChunk(writer, &program.main);
    for (program.functions, 0..) |func, i| {
        try writer.print("=== fn {d} (arity={d}, locals={d}) ===\n", .{ i, func.arity, func.locals_count });
        try dumpChunk(writer, &func.chunk);
    }
}

fn dumpChunk(writer: *std.Io.Writer, bc: *const Bytecode) !void {
    try writer.writeAll("-- constants --\n");
    for (bc.constants, 0..) |value, i| {
        try writer.print("  [{d}] {any}\n", .{ i, value });
    }
    try writer.writeAll("-- code --\n");
    var pc: u32 = 0;
    while (pc < bc.code.len) {
        const op = bc.readOpcode(pc);
        try writer.print("  {x:0>4}  {s}", .{ pc, @tagName(op) });
        const size = Bytecode.operandSize(op);
        switch (size) {
            0 => {},
            1 => try writer.print(" {d}", .{bc.readByte(pc + 1)}),
            2 => try writer.print(" {d}", .{bc.readU16(pc + 1)}),
            4 => try writer.print(" {d}", .{bc.readU32(pc + 1)}),
            5 => try writer.print(" {d} {d}", .{ bc.readU32(pc + 1), bc.readByte(pc + 5) }),
            else => unreachable,
        }
        try writer.writeAll("\n");
        pc += 1 + size;
    }
}
fn computeLocalsPoolSize(program: *const Program, main_locals: u16, max_frames: usize) usize {
    var max_locals: u16 = main_locals;
    for (program.functions) |f| {
        if (f.locals_count > max_locals) max_locals = f.locals_count;
    }
    return @as(usize, max_locals) * max_frames;
}

