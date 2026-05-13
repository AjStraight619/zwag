const std = @import("std");
const vaxis = @import("vaxis");
const log = @import("log.zig");
const cli = @import("cli/cli.zig");
const tui = @import("tui/tui.zig");

pub const panic = vaxis.panic_handler;

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = log.write,
};

pub fn main(init: std.process.Init) !void {
    log.init(init.io) catch |err| std.debug.print("log: {}\n", .{err});
    defer log.deinit();

    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len > 1) return cli.run(init, args);
    return tui.run(init);
}
