const std = @import("std");
const log = std.log;
const testing = std.testing;

pub const Token = struct {
    id: Id,
    loc: Loc,

    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    pub const keywords = std.ComptimeStringMap(Id, .{
        .{ "enum", .keyword_enum },
        .{ "message", .keyword_message },
        .{ "repeated", .keyword_repeated },
        .{ "oneof", .keyword_oneof },
        .{ "syntax", .keyword_syntax },
        .{ "package", .keyword_package },
        .{ "import", .keyword_import },
    });

    pub fn getKeyword(bytes: []const u8) ?Id {
        return keywords.get(bytes);
    }

    pub const Id = enum {
        // zig fmt: off
        eof,

        invalid,
        l_brace,          // {
        r_brace,          // }
        l_sbrace,         // [
        r_sbrace,         // ]
        l_paren,          // (
        r_paren,          // )
        dot,              // .
        comma,            // ,
        semicolon,        // ;
        equal,            // =

        string_literal,   // "something"
        int_literal,      // 1
        identifier,       // ident

        keyword_enum,     // enum { ... }
        keyword_message,  // message { ... }
        keyword_repeated, // repeated Type field = 5;
        keyword_oneof,    // oneof { ... }
        keyword_syntax,   // syntax = "proto3";
        keyword_package,  // package my_pkg;
        keyword_import,   // import "other.proto";
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

pub const Tokenizer = struct {
    buffer: []const u8,
    index: usize = 0,

    pub fn next(self: *Tokenizer) Token {
        var result = Token{
            .id = .eof,
            .loc = .{
                .start = self.index,
                .end = undefined,
            },
        };

        var state: union(enum) {
            start,
            identifier,
            string_literal,
            int_literal,
            slash,
            line_comment,
            multiline_comment,
            multiline_comment_end,
        } = .start;

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
                    '[' => {
                        result.id = .l_sbrace;
                        self.index += 1;
                        break;
                    },
                    ']' => {
                        result.id = .r_sbrace;
                        self.index += 1;
                        break;
                    },
                    '(' => {
                        result.id = .l_paren;
                        self.index += 1;
                        break;
                    },
                    ')' => {
                        result.id = .r_paren;
                        self.index += 1;
                        break;
                    },
                    ';' => {
                        result.id = .semicolon;
                        self.index += 1;
                        break;
                    },
                    '.' => {
                        result.id = .dot;
                        self.index += 1;
                        break;
                    },
                    ',' => {
                        result.id = .comma;
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
                    '/' => {
                        state = .slash;
                    },
                    '"' => {
                        result.id = .string_literal;
                        state = .string_literal;
                    },
                    else => {
                        result.id = .invalid;
                        result.loc.end = self.index;
                        self.index += 1;
                        return result;
                    },
                },
                .slash => switch (c) {
                    '/' => {
                        state = .line_comment;
                    },
                    '*' => {
                        state = .multiline_comment;
                    },
                    else => {
                        result.id = .invalid;
                        self.index += 1;
                        break;
                    },
                },
                .line_comment => switch (c) {
                    '\n' => {
                        state = .start;
                        result.loc.start = self.index + 1;
                    },
                    else => {},
                },
                .multiline_comment => switch (c) {
                    '*' => {
                        state = .multiline_comment_end;
                    },
                    else => {},
                },
                .multiline_comment_end => switch (c) {
                    '/' => {
                        state = .start;
                        result.loc.start = self.index + 1;
                    },
                    else => {
                        state = .multiline_comment;
                    },
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
                .string_literal => switch (c) {
                    '"' => {
                        self.index += 1;
                        break;
                    },
                    else => {}, // TODO validate characters/encoding
                },
            }
        }

        if (result.id == .eof) {
            result.loc.start = self.index;
        }

        result.loc.end = self.index;
        return result;
    }
};

fn testExpected(source: []const u8, expected: []const Token.Id) !void {
    var tokenizer = Tokenizer{
        .buffer = source,
    };
    for (expected) |exp, i| {
        const token = tokenizer.next();
        if (exp != token.id) {
            const stderr = std.io.getStdErr().writer();
            try stderr.print("Tokens don't match: (exp) {} != (giv) {} at pos {d}\n", .{ exp, token.id, i + 1 });
            return error.TestExpectedEqual;
        }
        try testing.expectEqual(exp, token.id);
    }
}

test "simple enum" {
    try testExpected(
        \\/*
        \\ * Some cool kind
        \\ */
        \\enum SomeKind
        \\{
        \\  // This generally means none
        \\  NONE = 0;
        \\  // This means A
        \\  // and only A
        \\  A = 1;
        \\  /* B * * * * */
        \\  B = 2;
        \\  // And this one is just a C
        \\  C = 3;
        \\}
    , &[_]Token.Id{
        // zig fmt: off
        .keyword_enum, .identifier,
        .l_brace,
            .identifier, .equal, .int_literal, .semicolon,
            .identifier, .equal, .int_literal, .semicolon,
            .identifier, .equal, .int_literal, .semicolon,
            .identifier, .equal, .int_literal, .semicolon,
        .r_brace,
        // zig fmt: on
    });
}

test "simple enum - weird formatting" {
    try testExpected(
        \\enum SomeKind {  NONE = 0;
        \\A = 1;
        \\       B = 2; C = 3;
        \\}
    , &[_]Token.Id{
        // zig fmt: off
        .keyword_enum, .identifier,
        .l_brace,
            .identifier, .equal, .int_literal, .semicolon,
            .identifier, .equal, .int_literal, .semicolon,
            .identifier, .equal, .int_literal, .semicolon,
            .identifier, .equal, .int_literal, .semicolon,
        .r_brace,
        // zig fmt: on
    });
}

test "simple message" {
    try testExpected(
        \\message MyMessage
        \\{
        \\  Ptr ptr_field = 1;
        \\  int32 ptr_len = 2;
        \\}
    , &[_]Token.Id{
        // zig fmt: off
        .keyword_message, .identifier,
        .l_brace,
            .identifier, .identifier, .equal, .int_literal, .semicolon,
            .identifier, .identifier, .equal, .int_literal, .semicolon,
        .r_brace,
        // zig fmt: on
    });
}

test "full proto spec file" {
    try testExpected(
        \\// autogen by super_proto_gen.py
        \\
        \\syntax = "proto3";
        \\
        \\package my_pkg;
        \\
        \\import "another.proto";
        \\
        \\message MsgA {
        \\  int32 field_1 = 1;
        \\  repeated Msg msgs = 2 [(nanopb).type=FT_POINTER];
        \\}
        \\
        \\// Tagged union y'all!
        \\message Msg {
        \\  oneof msg {
        \\    MsgA msg_a = 1 [json_name="msg_a"];
        \\    MsgB msg_b = 2 [ json_name = "msg_b" ];
        \\  }
        \\}
        \\
        \\/*
        \\ * Message B
        \\ */
        \\message MsgB {
        \\  // Some kind
        \\  Kind kind = 1;
        \\  // If the message is valid
        \\  bool valid = 2;
        \\}
        \\
        \\enum Kind {
        \\  KIND_NONE = 0;
        \\  KIND_A = 1;
        \\  KIND_B = 2;
        \\}
    , &[_]Token.Id{
        // zig fmt: off

        .keyword_syntax, .equal, .string_literal, .semicolon,

        .keyword_package, .identifier, .semicolon,

        .keyword_import, .string_literal, .semicolon,

        .keyword_message, .identifier,
        .l_brace,
            .identifier, .identifier, .equal, .int_literal, .semicolon,
            .keyword_repeated, .identifier, .identifier, .equal, .int_literal, .l_sbrace, .l_paren, .identifier, .r_paren, .dot, .identifier, .equal, .identifier, .r_sbrace, .semicolon,
        .r_brace,

        .keyword_message, .identifier,
        .l_brace,
            .keyword_oneof, .identifier,
            .l_brace,
                .identifier, .identifier, .equal, .int_literal, .l_sbrace, .identifier, .equal, .string_literal, .r_sbrace, .semicolon,
                .identifier, .identifier, .equal, .int_literal, .l_sbrace, .identifier, .equal, .string_literal, .r_sbrace, .semicolon,
            .r_brace,
        .r_brace,

        .keyword_message, .identifier,
        .l_brace,
            .identifier, .identifier, .equal, .int_literal, .semicolon,
            .identifier, .identifier, .equal, .int_literal, .semicolon,
        .r_brace,

        .keyword_enum, .identifier,
        .l_brace,
            .identifier, .equal, .int_literal, .semicolon,
            .identifier, .equal, .int_literal, .semicolon,
            .identifier, .equal, .int_literal, .semicolon,
        .r_brace,

        // zig fmt: on
    });
}
