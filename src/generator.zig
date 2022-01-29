const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const parser = @import("parser.zig");
const tokenizer = @import("tokenizer.zig");

const Allocator = mem.Allocator;
const Token = tokenizer.Token;
const ParseNode = parser.Node;
const ParseScope = parser.Scope;

const ErrorMsg = struct {
    msg: []const u8,
    // loc: usize,
};

const GenResult = union(enum) {
    ok: void,
    err: *ErrorMsg,
};

const GenError = error{
    OutOfMemory,
    GenFail,
} || std.fmt.ParseIntError;

pub const Generator = struct {
    arena: Allocator,
    buffer: []const u8,
    tokens: []const Token,
    parse_scope: *ParseScope,
    err_msg: ?*ErrorMsg = null,

    fn fail(gen: *Generator, comptime format: []const u8, args: anytype) GenError {
        assert(gen.err_msg == null);
        const err_msg = try gen.arena.create(ErrorMsg);
        err_msg.* = .{ .msg = try std.fmt.allocPrint(gen.arena, format, args) };
        gen.err_msg = err_msg;
        return error.GenFail;
    }

    pub fn generate(gen: *Generator, code: *std.ArrayList(u8)) !GenResult {
        gen.generateInternal(code) catch |err| switch (err) {
            error.GenFail => {
                return GenResult{ .err = gen.err_msg.? };
            },
            else => |e| return e,
        };
        return GenResult{ .ok = {} };
    }

    fn generateInternal(gen: *Generator, code: *std.ArrayList(u8)) GenError!void {
        for (gen.parse_scope.nodes.items) |node| {
            switch (node) {
                .@"enum" => {
                    // TODO verify at global scope that it wasn't redefined by any chance
                    try gen.generateEnum(node, code);
                },
                // else => {
                //     return gen.fail("TODO unhandled node type: {s}", .{@tagName(node)});
                // },
            }
        }
    }

    fn generateEnum(gen: *Generator, node: ParseNode, code: *std.ArrayList(u8)) GenError!void {
        // TODO these should be methods on respective wrapper structs like `Ast` in zig, etc.
        const enum_name_tok = gen.tokens[node.@"enum".name];
        const enum_name = gen.buffer[enum_name_tok.loc.start..enum_name_tok.loc.end];
        const writer = code.writer();
        try writer.print("pub const {s} = enum {{\n", .{enum_name});

        var field_names = std.StringHashMap(void).init(gen.arena);
        var field_values = std.AutoHashMap(usize, void).init(gen.arena);

        for (node.@"enum".fields.items) |field| {
            const field_name_tok = gen.tokens[field[0]];
            const field_name = gen.buffer[field_name_tok.loc.start..field_name_tok.loc.end];

            if (field_names.contains(field_name)) {
                return gen.fail("variant '{s}' already defined", .{field_name});
            }
            try field_names.putNoClobber(field_name, {});

            const field_value_tok = gen.tokens[field[1]];
            const field_value = try std.fmt.parseInt(
                usize,
                gen.buffer[field_value_tok.loc.start..field_value_tok.loc.end],
                10,
            );

            if (field_values.contains(field_value)) {
                return gen.fail("value '{d}' already assigned to a variant", .{field_value});
            }
            try field_values.putNoClobber(field_value, {});

            try writer.print("    {s} = {d},\n", .{ field_name, field_value });
        }

        try writer.writeAll("};");
    }
};
