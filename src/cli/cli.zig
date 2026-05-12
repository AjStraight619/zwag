const std = @import("std");
const parser = @import("parser.zig");
const manifest = @import("manifest");

pub fn run(init: std.process.Init, args: []const [:0]const u8) !void {
    _ = init;
    const cmd = parser.parse(args) catch |err| switch (err) {
        error.UnknownCommand => {
            printUsage();
            std.process.exit(1);
        },
    };
    switch (cmd) {
        .help => printHelp(),
        .version => printVersion(),
    }
}

fn printHelp() void {
    std.debug.print(
        \\zwag — terminal agent
        \\
        \\Usage:
        \\  zwag                  Launch the TUI
        \\  zwag --help, -h       Show this help
        \\  zwag --version, -V    Show version
        \\
    , .{});
}

fn printVersion() void {
    std.debug.print("{s} {s}\n", .{ @tagName(manifest.name), manifest.version });
}

fn printUsage() void {
    std.debug.print("zwag: unknown command. Try `zwag --help`.\n", .{});
}
