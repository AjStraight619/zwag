//! Disk persistence for conversations. Per-project: sessions live in
//! `./.zwag/sessions/<id>.json` relative to cwd. Synchronous; the files
//! are small enough that a worker isn't worth it.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Conversation = @import("Conversation.zig");

pub const SESSIONS_DIR = ".zwag/sessions";

/// Caller frees the returned timestamp string. Format: "YYYYMMDDTHHMMSS".
pub fn newId(gpa: Allocator) ![]u8 {
    // TODO: format current time as a sortable string.
    _ = gpa;
    return error.NotImplemented;
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
