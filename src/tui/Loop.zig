//! Thin wrapper around vaxis.Loop that owns the app's Event union.
//! All inter-thread communication flows through here.

const std = @import("std");
const Allocator = std.mem.Allocator;
const vaxis = @import("vaxis");

pub const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    text_delta: []const u8,
    thinking_start,
    thinking_end,
    err: []const u8,
    stream_done,
};

pub fn freeOwned(gpa: Allocator, ev: Event) void {
    switch (ev) {
        .text_delta, .err => |bytes| gpa.free(bytes),
        else => {},
    }
}

const Loop = @This();

inner: vaxis.Loop(Event),

pub fn init(io: std.Io, tty: *vaxis.Tty, vx: *vaxis.Vaxis) Loop {
    return .{ .inner = .init(io, tty, vx) };
}

pub fn start(self: *Loop) !void {
    return self.inner.start();
}

pub fn stop(self: *Loop) void {
    self.inner.stop();
}

pub fn nextEvent(self: *Loop) !Event {
    return self.inner.nextEvent();
}

pub fn postEvent(self: *Loop, event: Event) !void {
    return self.inner.postEvent(event);
}

/// Drain queued events without processing them, freeing heap payloads.
/// Use during shutdown so events posted by the worker after cancel
/// (e.g. a final err event) don't leak.
pub fn drain(self: *Loop, gpa: Allocator) void {
    while (self.inner.tryEvent() catch null) |ev| freeOwned(gpa, ev);
}
