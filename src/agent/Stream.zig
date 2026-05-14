//! Background worker for agent streaming (SSE). Spawned by
//! start(), posts events back to the main thread via the Loop.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Loop = @import("../tui/Loop.zig");
const Event = Loop.Event;
const Client = @import("../net/Client.zig");
const stream_event = @import("../net/event.zig");
const Conversation = @import("../conversation/Conversation.zig");

const log = std.log.scoped(.stream);

const Stream = @This();

pub const Phase = enum { idle, thinking, responding };

pub const BlockKind = enum { none, text, thinking, tool_use };

gpa: Allocator,
io: Io,
loop: *Loop,
client: Client,

/// main-thread only
phase: Phase = .idle,
/// worker-thread only — which content_block kind we're currently inside
current_block: BlockKind = .none,
in_flight: ?Io.Future(anyerror!void) = null,

pub fn init(gpa: Allocator, io: Io, loop: *Loop, api_key: []const u8) !Stream {
    return .{
        .gpa = gpa,
        .io = io,
        .loop = loop,
        .client = try Client.init(gpa, io, api_key, Client.DEFAULT_BASE_URL),
    };
}

pub fn deinit(self: *Stream) void {
    if (self.in_flight) |*f| f.cancel(self.io) catch {};
    self.client.deinit();
}

pub fn isActive(self: Stream) bool {
    return self.phase != .idle;
}

pub fn start(self: *Stream, history: []const Conversation.Message) !void {
    if (self.in_flight != null) return;
    self.phase = .thinking;
    self.in_flight = try self.io.concurrent(runStream, .{ self, history });
}

pub fn dispatch(self: *Stream, event: Event) void {
    switch (event) {
        .thinking_start => self.phase = .thinking,
        .thinking_end => self.phase = .responding,
        .text_delta => if (self.phase == .thinking) {
            self.phase = .responding;
        },
        .stream_done => {
            self.phase = .idle;
            if (self.in_flight) |*f| {
                f.await(self.io) catch |err| log.err("stream: {}", .{err});
                self.in_flight = null;
            }
        },
        else => {},
    }
}

fn postOwnedEvent(self: *Stream, comptime field: []const u8, text: []const u8) !void {
    const owned = try self.gpa.dupe(u8, text);
    errdefer self.gpa.free(owned);
    try self.loop.postEvent(@unionInit(Event, field, owned));
}

fn runStream(self: *Stream, history: []const Conversation.Message) anyerror!void {
    defer self.loop.postEvent(.stream_done) catch {};

    var messages: std.ArrayList(Client.Message) = try .initCapacity(self.gpa, history.len);
    defer messages.deinit(self.gpa);
    for (history) |m| {
        const role: Client.Role = switch (m.role) {
            .user => .user,
            .assistant => .assistant,
            .system => continue,
        };
        messages.appendAssumeCapacity(.{ .role = role, .content = m.content.items });
    }

    const req: Client.MessageRequest = .{
        .model = "claude-haiku-4-5-20251001",
        .messages = messages.items,
        .thinking = .{},
    };

    self.client.streamMessages(req, self, onSse) catch |err| {
        self.postOwnedEvent("err", @errorName(err)) catch {};
        return err;
    };
}

fn onSse(self: *Stream, ev: stream_event.StreamEvent) anyerror!void {
    log.debug("sse event: {s}", .{@tagName(ev)});
    switch (ev) {
        .content_block_start => |b| {
            log.debug("content_block_start type={s}", .{b.content_block.type});
            self.current_block = std.meta.stringToEnum(BlockKind, b.content_block.type) orelse .none;
            if (self.current_block == .thinking) {
                log.info("worker: entering thinking block", .{});
                try self.loop.postEvent(.thinking_start);
            }
        },
        .content_block_delta => |d| {
            log.debug("content_block_delta delta_type={s} text_present={}", .{
                d.delta.type, d.delta.text != null,
            });
            const text = d.delta.text orelse return;
            try self.postOwnedEvent("text_delta", text);
        },
        .content_block_stop => {
            if (self.current_block == .thinking) {
                log.info("worker: exiting thinking block", .{});
                try self.loop.postEvent(.thinking_end);
            }
            self.current_block = .none;
        },
        .err => |e| try self.postOwnedEvent("err", e.@"error".message),
        else => {},
    }
}
