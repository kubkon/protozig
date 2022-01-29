const std = @import("std");
const assert = std.debug.assert;
const log = std.log;
const mem = std.mem;
const tokenizer = @import("tokenizer.zig");

const Allocator = mem.Allocator;
const TokenIndex = tokenizer.TokenIndex;
const TokenIterator = tokenizer.TokenIterator;
const Tokenizer = tokenizer.Tokenizer;
const Token = tokenizer.Token;

pub const Scope = struct {
    nodes: std.ArrayListUnmanaged(Node) = .{},
};

const Loc = struct {
    start: TokenIndex,
    end: TokenIndex,
};

pub const Node = union(enum) {
    @"enum": EnumNode,
};

const EnumNode = struct {
    loc: Loc,
    name: TokenIndex,
    fields: std.ArrayListUnmanaged(FieldTuple) = .{},

    const FieldTuple = std.meta.Tuple(&[_]type{ TokenIndex, TokenIndex });
};

const ParseError = error{
    OutOfMemory,
    ParseFail,
};

const ParseResult = union(enum) {
    ok: void,
    err: *ErrorMsg,
};

const ErrorMsg = struct {
    msg: []const u8,
    loc: TokenIndex,
};

pub const Parser = struct {
    arena: Allocator,
    token_it: *TokenIterator,
    scope: *Scope,
    err_msg: ?*ErrorMsg = null,

    fn fail(parser: *Parser, comptime format: []const u8, args: anytype) ParseError {
        assert(parser.err_msg == null);
        const err_msg = try parser.arena.create(ErrorMsg);
        err_msg.* = .{
            .msg = try std.fmt.allocPrint(parser.arena, format, args),
            .loc = parser.token_it.pos,
        };
        parser.err_msg = err_msg;
        return error.ParseFail;
    }

    pub fn parse(parser: *Parser) !ParseResult {
        parser.parseInternal() catch |err| switch (err) {
            error.ParseFail => {
                return ParseResult{ .err = parser.err_msg.? };
            },
            else => |e| return e,
        };
        return ParseResult{ .ok = {} };
    }

    fn parseInternal(parser: *Parser) ParseError!void {
        while (true) {
            const pos = parser.token_it.pos;
            const token = parser.token_it.next();
            if (token.id == .eof) break;

            switch (token.id) {
                .keyword_enum => {
                    try parser.parseEnum(pos);
                },
                else => {
                    return parser.fail("TODO unhandled token", .{});
                },
            }
        }
    }

    fn parseEnum(parser: *Parser, start: TokenIndex) ParseError!void {
        var enum_node = EnumNode{
            .loc = .{
                .start = start,
                .end = undefined,
            },
            .name = undefined,
        };
        enum_node.name = try parser.expectToken(.identifier);
        _ = try parser.expectToken(.l_brace);

        while (true) {
            const pos = parser.token_it.pos;
            const token = parser.token_it.next();

            switch (token.id) {
                .identifier => {
                    const field_name = pos;
                    _ = try parser.expectToken(.equal);
                    const field_value = try parser.expectToken(.int_literal);
                    _ = try parser.expectToken(.semicolon);
                    try enum_node.fields.append(parser.arena, .{ field_name, field_value });
                },
                .r_brace => {
                    enum_node.loc.end = pos;
                    break;
                },
                else => {
                    return parser.fail("unexpected token: {}", .{token.id});
                },
            }
        }

        // log.debug("enum := {}", .{enum_node});

        try parser.scope.nodes.append(parser.arena, Node{
            .@"enum" = enum_node,
        });
    }

    fn expectToken(parser: *Parser, id: Token.Id) ParseError!TokenIndex {
        const pos = parser.token_it.pos;
        _ = parser.token_it.peek() orelse return parser.fail("unexpected end of file", .{});
        const token = parser.token_it.next();
        if (token.id == id) {
            return pos;
        } else {
            parser.token_it.seekTo(pos);
            return parser.fail("wrong token: expected {}, found {}", .{
                id, token.id,
            });
        }
    }
};
