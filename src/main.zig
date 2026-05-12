const std = @import("std");
const Lexer = @import("Lexer.zig");
const Ast = @import("./Structures/Ast.zig");
const Parser = @import("Parser.zig");
const Resolver = @import("Resolver.zig");
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

    // Run the resolver — annotates AST nodes with slots.
    var resolver = Resolver.init();
    defer resolver.deinit(allocator);
    try resolver.resolve(allocator, ast);

    // Dump the resolved AST.
    for (ast) |statement| {
        try dumpStmt(&c_writer.interface, statement, 0);
    }
    try c_writer.interface.flush();
}

fn writeIndent(writer: *std.Io.Writer, indent: u32) !void {
    for (0..indent) |_| try writer.writeAll("  ");
}
fn dumpStmt(writer: *std.Io.Writer, stmt: *const Ast.Statement, indent: u32) !void {
    try writeIndent(writer, indent);
    switch (stmt.*) {
        .var_dclr => |v| {
            const kw = if (v.is_mutable) "var" else "const";
            try writer.print("{s} {s}", .{ kw, v.name });
            if (v.type_annotation) |t| try writer.print(": {s}", .{t});
            try writer.print(" [slot={?d}] = ", .{v.slot});
            try dumpExpr(writer, v.value);
            try writer.writeAll("\n");
        },
        .assign => |a| {
            try writer.print("{s} [slot={?d}] = ", .{ a.name, a.slot });
            try dumpExpr(writer, a.value);
            try writer.writeAll("\n");
        },
        .if_stmt => |i| {
            try writer.writeAll("if ");
            try dumpExpr(writer, i.condition);
            try writer.writeAll("\n");
            for (i.then_branch) |s| try dumpStmt(writer, s, indent + 1);
            if (i.else_branch) |branch| {
                try writeIndent(writer, indent);
                try writer.writeAll("else\n");
                for (branch) |s| try dumpStmt(writer, s, indent + 1);
            }
        },
        .while_stmt => |w| {
            try writer.writeAll("while ");
            try dumpExpr(writer, w.condition);
            try writer.writeAll("\n");
            for (w.then_branch) |s| try dumpStmt(writer, s, indent + 1);
        },
        .expression => |e| {
            try dumpExpr(writer, e);
            try writer.writeAll("\n");
        },
    }
}

fn dumpExpr(writer: *std.Io.Writer, expr: *const Ast.Expression) !void {
    switch (expr.*) {
        .literal => |v| try writer.print("{any}", .{v}),
        .identifier => |id| try writer.print("{s}[slot={?d}]", .{ id.name, id.slot }),
        .binary => |b| {
            try writer.writeAll("(");
            try dumpExpr(writer, b.left);
            try writer.print(" {s} ", .{@tagName(b.op)});
            try dumpExpr(writer, b.right);
            try writer.writeAll(")");
        },
        .unary => |u| {
            try writer.print("({s} ", .{@tagName(u.op)});
            try dumpExpr(writer, u.operand);
            try writer.writeAll(")");
        },
        .grouping => |inner| {
            try writer.writeAll("(");
            try dumpExpr(writer, inner);
            try writer.writeAll(")");
        },
    }
}
