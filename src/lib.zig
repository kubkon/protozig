const std = @import("std");
const mem = std.mem;
const testing = std.testing;

pub const generator = @import("generator.zig");
pub const parser = @import("parser.zig");
pub const tokenizer = @import("tokenizer.zig");

test {
    testing.refAllDecls(@This());
}

const Allocator = mem.Allocator;
const Generator = generator.Generator;
const Parser = parser.Parser;
const Scope = parser.Scope;
const Tokenizer = tokenizer.Tokenizer;
const Token = tokenizer.Token;
const TokenIndex = tokenizer.TokenIndex;
const TokenIterator = tokenizer.TokenIterator;

pub const Result = union(enum) {
    ok: []const u8,
    err: []const u8,
};

pub fn generate(gpa: Allocator, source: []const u8) !Result {
    var arena_alloc = std.heap.ArenaAllocator.init(gpa);
    defer arena_alloc.deinit();
    const arena = arena_alloc.allocator();

    var ttokenizer = Tokenizer{ .buffer = source };
    var tokens = std.ArrayList(Token).init(arena);

    while (true) {
        const token = ttokenizer.next();
        try tokens.append(token);
        if (token.id == .eof) break;
    }

    var token_it = TokenIterator{ .buffer = tokens.items };
    var scope = Scope{};
    var pparser = Parser{
        .arena = arena,
        .token_it = &token_it,
        .scope = &scope,
    };
    switch (try pparser.parse()) {
        .ok => {},
        .err => |err_msg| {
            var msg = std.ArrayList(u8).init(gpa);
            defer msg.deinit();

            const token = token_it.buffer[err_msg.loc];
            // TODO restore the immediate parent scope for error handling
            const loc = try std.fmt.allocPrint(arena, "{s}\n", .{source[token.loc.start..token.loc.end]});
            try msg.appendSlice(loc);
            try msg.appendSlice(err_msg.msg);

            return Result{ .err = msg.toOwnedSlice() };
        },
    }

    var code = std.ArrayList(u8).init(gpa);
    defer code.deinit();

    var ggenerator = Generator{
        .arena = arena,
        .buffer = source,
        .tokens = tokens.items,
        .parse_scope = &scope,
    };
    switch (try ggenerator.generate(&code)) {
        .ok => {},
        .err => |err_msg| {
            return Result{ .err = err_msg.msg };
        },
    }

    return Result{ .ok = code.toOwnedSlice() };
}
