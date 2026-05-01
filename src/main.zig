const std = @import("std");
const Lexer = @import("Lexer.zig");
const Interpreter = @import("Interpreter.zig");
const Parser = @import("Parser.zig");
const Io = std.Io;

const Z = @import("Z");

pub fn main(init: std.process.Init) !void {
    var c_buffer: [4096]u8 = undefined;
    var c_writer = std.Io.File.stdout().writer(init.io, &c_buffer);

    var lex = Lexer.init("21 * 2");
    var parser = Parser.init(&lex);
    var ast = try parser.parse(init.gpa);
    defer ast.deinit(init.gpa);
    var interpreter = Interpreter.init();
    const results = try interpreter.execute(ast, init.gpa);
    defer init.gpa.free(results);

    try c_writer.interface.print("{s}", .{results});

    try c_writer.interface.flush(); // Don't forget to flush!!!!
}
