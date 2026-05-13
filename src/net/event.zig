const std = @import("std");
const Allocator = std.mem.Allocator;
const sse = @import("sse.zig");

pub const ContentBlockStart = struct {
    index: u32,
    content_block: struct {
        type: []const u8,
        id: ?[]const u8 = null,
        name: ?[]const u8 = null,
    },
};

pub const ContentBlockDelta = struct {
    index: u32,
    delta: struct {
        type: []const u8,
        text: ?[]const u8 = null,
        partial_json: ?[]const u8 = null,
    },
};

pub const MessageDelta = struct {
    delta: struct {
        stop_reason: ?[]const u8 = null,
    },
};

pub const ErrorPayload = struct {
    @"error": struct {
        type: []const u8,
        message: []const u8,
    },
};

pub const StreamEvent = union(enum) {
    message_start,
    content_block_start: ContentBlockStart,
    content_block_delta: ContentBlockDelta,
    content_block_stop,
    message_delta: MessageDelta,
    message_stop,
    ping,
    err: ErrorPayload,
    /// Forward-compat hook: any event name we don't recognize lands here
    /// instead of failing the stream.
    unknown: sse.Event,
};

pub const DecodeError = std.json.ParseError(std.json.Scanner);

pub fn decode(arena: Allocator, raw: sse.Event) DecodeError!StreamEvent {
    const opts: std.json.ParseOptions = .{ .ignore_unknown_fields = true };

    if (std.mem.eql(u8, raw.name, "message_start")) return .message_start;
    if (std.mem.eql(u8, raw.name, "content_block_start"))
        return .{ .content_block_start = try parse(ContentBlockStart, arena, raw.data, opts) };
    if (std.mem.eql(u8, raw.name, "content_block_delta"))
        return .{ .content_block_delta = try parse(ContentBlockDelta, arena, raw.data, opts) };
    if (std.mem.eql(u8, raw.name, "content_block_stop")) return .content_block_stop;
    if (std.mem.eql(u8, raw.name, "message_delta"))
        return .{ .message_delta = try parse(MessageDelta, arena, raw.data, opts) };
    if (std.mem.eql(u8, raw.name, "message_stop")) return .message_stop;
    if (std.mem.eql(u8, raw.name, "ping")) return .ping;
    if (std.mem.eql(u8, raw.name, "error"))
        return .{ .err = try parse(ErrorPayload, arena, raw.data, opts) };

    return .{ .unknown = raw };
}

fn parse(comptime T: type, arena: Allocator, data: []const u8, opts: std.json.ParseOptions) DecodeError!T {
    return std.json.parseFromSliceLeaky(T, arena, data, opts);
}

test "decode content_block_delta with text_delta" {
    const t = std.testing;
    var arena: std.heap.ArenaAllocator = .init(t.allocator);
    defer arena.deinit();

    const ev = try decode(arena.allocator(), .{
        .name = "content_block_delta",
        .data =
        \\{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hello"}}
        ,
    });

    try t.expectEqualStrings("text_delta", ev.content_block_delta.delta.type);
    try t.expectEqualStrings("hello", ev.content_block_delta.delta.text.?);
}

test "decode message_start and message_stop are tag-only" {
    const t = std.testing;
    var arena: std.heap.ArenaAllocator = .init(t.allocator);
    defer arena.deinit();

    const start = try decode(arena.allocator(), .{ .name = "message_start", .data = "{}" });
    const stop = try decode(arena.allocator(), .{ .name = "message_stop", .data = "{}" });

    try t.expectEqual(StreamEvent.message_start, start);
    try t.expectEqual(StreamEvent.message_stop, stop);
}

test "decode message_delta with stop_reason" {
    const t = std.testing;
    var arena: std.heap.ArenaAllocator = .init(t.allocator);
    defer arena.deinit();

    const ev = try decode(arena.allocator(), .{
        .name = "message_delta",
        .data =
        \\{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":42}}
        ,
    });

    try t.expectEqualStrings("end_turn", ev.message_delta.delta.stop_reason.?);
}

test "decode error event" {
    const t = std.testing;
    var arena: std.heap.ArenaAllocator = .init(t.allocator);
    defer arena.deinit();

    const ev = try decode(arena.allocator(), .{
        .name = "error",
        .data =
        \\{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}
        ,
    });

    try t.expectEqualStrings("overloaded_error", ev.err.@"error".type);
    try t.expectEqualStrings("Overloaded", ev.err.@"error".message);
}

test "unknown event name preserved" {
    const t = std.testing;
    var arena: std.heap.ArenaAllocator = .init(t.allocator);
    defer arena.deinit();

    const ev = try decode(arena.allocator(), .{ .name = "future_event", .data = "{}" });
    try t.expectEqualStrings("future_event", ev.unknown.name);
}
