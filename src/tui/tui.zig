//! TUI mode entry point. Owns the composition root: tty, vx, loop, app.

const std = @import("std");
const vaxis = @import("vaxis");

const App = @import("../App.zig");
const Loop = @import("Loop.zig");
const utils = @import("../utils.zig");
const Provider = @import("../net/Provider.zig").Provider;

pub fn run(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    utils.loadEnvFile(io, gpa, init.environ_map, ".env") catch |err| {
        std.log.warn(".env load: {}", .{err});
    };

    const provider: Provider = .anthropic;
    const env_key = provider.envKey() orelse return error.MissingApiKey;
    const api_key = init.environ_map.get(env_key) orelse {
        std.log.err("{s} not set", .{env_key});
        return error.MissingApiKey;
    };

    var buffer: [1024]u8 = undefined;
    var tty: vaxis.Tty = try .init(io, &buffer);
    defer tty.deinit();

    var vx = try vaxis.init(io, gpa, init.environ_map, .{});
    defer vx.deinit(gpa, tty.writer());

    var loop: Loop = .init(io, &tty, &vx);
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), .fromSeconds(1));

    var app = try App.init(gpa, io, &tty, &vx, &loop, api_key);
    defer app.deinit();

    try app.run();
}
