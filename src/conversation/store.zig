//! Disk persistence for conversations. Per-project: sessions live in
//! `./.zwag/sessions/<id>.json` relative to cwd. Synchronous; the files
//! are small enough that a worker isn't worth it.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Conversation = @import("Conversation.zig");

pub const SESSIONS_DIR = ".zwag/sessions";

/// Caller frees the returned id string.
/// Format: "YYYYMMDDTHHMMSS-xxxxxxxx" — UTC timestamp first (so `ls` sorts
/// chronologically) plus 4 random hex bytes to avoid collisions within
/// the same second.
pub fn newId(io: Io, gpa: Allocator) ![]u8 {
    const ts = Io.Timestamp.now(io, .real);
    const secs: u64 = @intCast(@divTrunc(ts.nanoseconds, std.time.ns_per_s));
    const epoch_secs: std.time.epoch.EpochSeconds = .{ .secs = secs };

    const year_day = epoch_secs.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_secs = epoch_secs.getDaySeconds();

    var rand_bytes: [4]u8 = undefined;
    io.random(&rand_bytes);
    const hex = std.fmt.bytesToHex(rand_bytes, .lower);

    return std.fmt.allocPrint(gpa, "{d:0>4}{d:0>2}{d:0>2}T{d:0>2}{d:0>2}{d:0>2}-{s}", .{
        year_day.year,
        @intFromEnum(month_day.month),
        @as(u6, month_day.day_index) + 1,
        day_secs.getHoursIntoDay(),
        day_secs.getMinutesIntoHour(),
        day_secs.getSecondsIntoMinute(),
        &hex,
    });
}

/// Ensure SESSIONS_DIR exists under cwd. No-op if already present.
pub fn ensureDir(io: Io) !void {
    // TODO: std.Io.Dir.cwd().makePath(io, SESSIONS_DIR)
    _ = io;
    return error.NotImplemented;
}

/// Save conversation as JSON to `<SESSIONS_DIR>/<id>.json`.
/// Overwrites if the file exists.
pub fn save(io: Io, gpa: Allocator, id: []const u8, conv: *const Conversation) !void {
    // TODO: ensureDir; build "<dir>/<id>.json" path; toJsonAlloc; write bytes.
    _ = io;
    _ = gpa;
    _ = id;
    _ = conv;
    return error.NotImplemented;
}

/// Load conversation from `<SESSIONS_DIR>/<id>.json`.
pub fn load(io: Io, gpa: Allocator, id: []const u8) !Conversation {
    // TODO: read file into bytes; Conversation.fromJson(gpa, bytes).
    _ = io;
    _ = gpa;
    _ = id;
    return error.NotImplemented;
}

/// List all session ids present in the sessions dir, newest-first.
/// Caller owns the slice and each id within.
pub fn list(io: Io, gpa: Allocator) ![][]u8 {
    // TODO: iterate SESSIONS_DIR, strip ".json" suffix, sort descending.
    _ = io;
    _ = gpa;
    return error.NotImplemented;
}
