const std = @import("std");
const vaxis = @import("vaxis");
const App = @import("App.zig");
const log = @import("log.zig");
const utils = @import("utils.zig");

pub const panic = vaxis.panic_handler;

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = log.write,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    log.init(io) catch |err| std.debug.print("log: {}\n", .{err});
    defer log.deinit();

    utils.loadEnvFile(io, gpa, init.environ_map, ".env") catch |err| {
        std.log.warn(".env load: {}", .{err});
    };

    const api_key = init.environ_map.get("ANTHROPIC_API_KEY") orelse {
        std.log.err("ANTHROPIC_API_KEY not set", .{});
        return error.MissingApiKey;
    };

    var buffer: [1024]u8 = undefined;
    var tty: vaxis.Tty = try .init(io, &buffer);
    defer tty.deinit();

    var vx = try vaxis.init(io, gpa, init.environ_map, .{});
    defer vx.deinit(gpa, tty.writer());

    var loop: App.Loop = .init(io, &tty, &vx);
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), .fromSeconds(1));

    var app = try App.init(gpa, io, &tty, &vx, &loop, api_key);
    defer app.deinit();

    try app.run();
}
