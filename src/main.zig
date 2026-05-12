const std = @import("std");
const Lexer = @import("Lexer.zig");
const Ast = @import("Structures/Ast.zig");
const Parser = @import("Parser.zig");
const Resolver = @import("Resolver.zig");
const TypeChecker = @import("TypeChecker.zig");
const Compiler = @import("Compiler.zig");
const Bytecode = @import("Bytecode.zig");
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

    var resolver = Resolver.init();
    defer resolver.deinit(allocator);
    try resolver.resolve(allocator, ast);

    var type_checker = TypeChecker.init();
    defer type_checker.deinit(allocator);
    try type_checker.check(allocator, ast);

    var compiler = Compiler.init();
    defer compiler.deinit(allocator);
    var bytecode = try compiler.compile(allocator, ast);
    defer bytecode.deinit(allocator);

    try dumpBytecode(writer, &bytecode);
    try writer.flush();
}

fn dumpBytecode(writer: *std.Io.Writer, bc: *const Bytecode) !void {
    try writer.writeAll("=== constants ===\n");
    for (bc.constants, 0..) |value, i| {
        try writer.print("  [{d}] {any}\n", .{ i, value });
    }

    try writer.writeAll("=== code ===\n");
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
            else => unreachable,
        }

        try writer.writeAll("\n");
        pc += 1 + size;
    }
}

