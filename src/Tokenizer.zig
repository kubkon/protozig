const Tokenizer = @This();

const std = @import("std");
const log = std.log;
const testing = std.testing;

buffer: []const u8,
index: usize = 0,

pub const Token = struct {
    id: Id,
    loc: Loc,

    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    pub const keywords = std.ComptimeStringMap(Id, .{
        .{ "enum", .keyword_enum },
    });

    pub fn getKeyword(bytes: []const u8) ?Id {
        return keywords.get(bytes);
    }

    pub const Id = enum {
        // zig fmt: off
        eof,
        l_brace,      // {
        r_brace,      // }
        semicolon,    // ;
        equal,        // =
        int_literal,  // 1
        identifier,   // ident
        keyword_enum, // enum
        // zig fmt: on
    };
};

pub const TokenIndex = usize;

pub const TokenIterator = struct {
    buffer: []const Token,
    pos: TokenIndex = 0,

    pub fn next(self: *TokenIterator) Token {
        const token = self.buffer[self.pos];
        self.pos += 1;
        return token;
    }

    pub fn peek(self: TokenIterator) ?Token {
        if (self.pos >= self.buffer.len) return null;
        return self.buffer[self.pos];
    }

    pub fn reset(self: *TokenIterator) void {
        self.pos = 0;
    }

    pub fn seekTo(self: *TokenIterator, pos: TokenIndex) void {
        self.pos = pos;
    }

    pub fn seekBy(self: *TokenIterator, offset: isize) void {
        const new_pos = @bitCast(isize, self.pos) + offset;
        if (new_pos < 0) {
            self.pos = 0;
        } else {
            self.pos = @intCast(usize, new_pos);
        }
    }
};

pub fn next(self: *Tokenizer) Token {
    var result = Token{
        .id = .eof,
        .loc = .{
            .start = self.index,
            .end = undefined,
        },
    };

    var state: union(enum) { start, identifier, int_literal } = .start;

    while (self.index < self.buffer.len) : (self.index += 1) {
        const c = self.buffer[self.index];
        switch (state) {
            .start => switch (c) {
                ' ', '\t', '\n', '\r' => {
                    result.loc.start = self.index + 1;
                },
                'a'...'z', 'A'...'Z', '_' => {
                    state = .identifier;
                    result.id = .identifier;
                },
                '{' => {
                    result.id = .l_brace;
                    self.index += 1;
                    break;
                },
                '}' => {
                    result.id = .r_brace;
                    self.index += 1;
                    break;
                },
                ';' => {
                    result.id = .semicolon;
                    self.index += 1;
                    break;
                },
                '0'...'9' => {
                    state = .int_literal;
                    result.id = .int_literal;
                },
                '=' => {
                    result.id = .equal;
                    self.index += 1;
                    break;
                },
                else => {},
            },
            .identifier => switch (c) {
                'a'...'z', 'A'...'Z', '_', '0'...'9' => {},
                else => {
                    if (Token.getKeyword(self.buffer[result.loc.start..self.index])) |id| {
                        result.id = id;
                    }
                    break;
                },
            },
            .int_literal => switch (c) {
                '0'...'9' => {},
                else => {
                    break;
                },
            },
        }
    }

    if (result.id == .eof) {
        result.loc.start = self.index;
    }

    result.loc.end = self.index;
    return result;
}

fn testExpected(source: []const u8, expected: []const Token.Id) !void {
    var tokenizer = Tokenizer{
        .buffer = source,
    };
    for (expected) |exp| {
        const token = tokenizer.next();
        try testing.expectEqual(exp, token.id);
    }
}

test "simple enum" {
    try testExpected(
        \\enum SomeKind {
        \\  NONE = 0;
        \\  A = 1;
        \\  B = 2;
        \\  C = 3;
        \\}
    , &[_]Token.Id{
        .keyword_enum,
        .identifier,
        .l_brace,
        .identifier,
        .equal,
        .int_literal,
        .semicolon,
        .identifier,
        .equal,
        .int_literal,
        .semicolon,
        .identifier,
        .equal,
        .int_literal,
        .semicolon,
        .identifier,
        .equal,
        .int_literal,
        .semicolon,
        .r_brace,
    });
}

test "simple enum - weird formatting" {
    try testExpected(
        \\enum SomeKind {  NONE = 0;
        \\A = 1;
        \\       B = 2; C = 3;
        \\}
    , &[_]Token.Id{
        .keyword_enum,
        .identifier,
        .l_brace,
        .identifier,
        .equal,
        .int_literal,
        .semicolon,
        .identifier,
        .equal,
        .int_literal,
        .semicolon,
        .identifier,
        .equal,
        .int_literal,
        .semicolon,
        .identifier,
        .equal,
        .int_literal,
        .semicolon,
        .r_brace,
    });
}
