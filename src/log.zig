//! Process-global file logger. Writes are mutex-serialized so the
//! main thread and SSE worker can't interleave bytes.

const std = @import("std");

const State = struct {
    file: std.Io.File,
    io: std.Io,
    mutex: std.Io.Mutex = .init,
};

var state: ?State = null;

pub fn init(io: std.Io) !void {
    state = .{
        .file = try std.Io.Dir.cwd().createFile(io, "zwag.log", .{}),
        .io = io,
    };
}

pub fn deinit() void {
    const s = state orelse return;
    s.file.close(s.io);
    state = null;
}

pub fn write(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime level.asText();
    const scope_part = comptime if (scope == .default) ": " else " (" ++ @tagName(scope) ++ "): ";

    var buf: [8192]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, level_txt ++ scope_part ++ format ++ "\n", args) catch return;

    if (state) |*s| {
        s.mutex.lockUncancelable(s.io);
        defer s.mutex.unlock(s.io);
        s.file.writeStreamingAll(s.io, out) catch return;
    } else {
        std.debug.print("{s}", .{out});
    }
}
