const std = @import("std");
const Lexer = @import("Lexer.zig");
const Interpreter = @import("Interpreter.zig");
const Parser = @import("Parser.zig");
const Io = std.Io;

const Z = @import("Z");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    var c_buffer: [4096]u8 = undefined;
    var c_writer = std.Io.File.stdout().writer(init.io, &c_buffer);

    var lex = Lexer.init(@embedFile("./Index.txt"));
    var parser = Parser.init(&lex);
    const ast = try parser.parse(allocator);
    defer {
        for (ast) |stmt| stmt.deinit(allocator);
        allocator.free(ast);
    }

    var interpreter = Interpreter.init(allocator);
    defer interpreter.deinit();

    const results = try interpreter.execute(ast, allocator);
    defer allocator.free(results);

    try c_writer.interface.print("{s}", .{results});
    try c_writer.interface.flush();
}
