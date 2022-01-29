const std = @import("std");
const fmt = std.fmt;
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const process = std.process;

const protozig = @import("lib.zig");

var gpa_alloc = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_alloc.allocator();

const usage =
    \\Usage: protozig <path-to-proto-file>
    \\
    \\General options:
    \\-h, --help    Print this help and exit
;

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    exit: {
        const msg = fmt.allocPrint(gpa, "fatal: " ++ format, args) catch break :exit;
        defer gpa.free(msg);
        io.getStdErr().writeAll(msg) catch {};
    }
    process.exit(1);
}

pub fn main() !void {
    var arena_allocator = std.heap.ArenaAllocator.init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    const args = try std.process.argsAlloc(arena);
    if (args.len == 1) {
        fatal("no input file specified", .{});
    }

    const stdout = io.getStdOut().writer();
    const stderr = io.getStdErr().writer();
    _ = stderr;
    if (mem.eql(u8, "-h", args[1]) or mem.eql(u8, "--help", args[1])) {
        try stdout.writeAll(usage);
        return;
    }

    const proto_file_path = args[1];
    const proto_file = try fs.cwd().openFile(proto_file_path, .{});
    defer proto_file.close();
    const raw_contents = try proto_file.readToEndAlloc(arena, std.math.maxInt(u32));

    const res = try protozig.generate(gpa, raw_contents);
    switch (res) {
        .ok => |code| {
            defer gpa.free(code);
        },
        .err => |err_msg| {
            try stderr.writeAll(err_msg);
            try stderr.writeByte('\n');
        },
    }
}
