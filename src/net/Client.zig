//! HTTP client for the Anthropic Messages API. streamMessages drives
//! an SSE response synchronously and invokes a caller-supplied callback
//! per decoded event.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const sse = @import("sse.zig");
const event = @import("event.zig");

const log = std.log.scoped(.net);

const Client = @This();

pub const ANTHROPIC_VERSION = "2023-06-01";
pub const DEFAULT_BASE_URL = "https://api.anthropic.com";

pub const Role = enum { user, assistant };

pub const Message = struct {
    role: Role,
    content: []const u8,
};

pub const Thinking = struct {
    type: []const u8 = "enabled",
    budget_tokens: u32 = 2000,
};

pub const MessageRequest = struct {
    model: []const u8,
    max_tokens: u32 = 4096,
    messages: []const Message,
    stream: bool = true,
    thinking: ?Thinking = null,
};

gpa: Allocator,
io: Io,
api_key: []const u8,
base_url: []const u8,
http: std.http.Client,
decompress_buf: []u8,

pub fn init(gpa: Allocator, io: Io, api_key: []const u8, base_url: []const u8) !Client {
    return .{
        .gpa = gpa,
        .io = io,
        .api_key = api_key,
        .base_url = base_url,
        .http = .{ .allocator = gpa, .io = io },
        .decompress_buf = try gpa.alloc(u8, std.compress.flate.max_window_len),
    };
}

pub fn deinit(self: *Client) void {
    self.http.deinit();
    self.gpa.free(self.decompress_buf);
}

pub fn streamMessages(
    self: *Client,
    req: MessageRequest,
    ctx: anytype,
    comptime onEvent: fn (@TypeOf(ctx), event.StreamEvent) anyerror!void,
) !void {
    const url = try std.fmt.allocPrint(self.gpa, "{s}/v1/messages", .{self.base_url});
    defer self.gpa.free(url);
    const uri = try std.Uri.parse(url);

    const body = try std.json.Stringify.valueAlloc(self.gpa, req, .{ .emit_null_optional_fields = false });
    defer self.gpa.free(body);

    const has_thinking = std.mem.indexOf(u8, body, "\"thinking\":{") != null;
    log.info("POST {s} body_bytes={d} thinking_in_body={}", .{ url, body.len, has_thinking });
    log.debug("request body: {s}", .{body});

    var http_req = try self.http.request(.POST, uri, .{
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
            .{ .name = "accept", .value = "text/event-stream" },
            .{ .name = "x-api-key", .value = self.api_key },
            .{ .name = "anthropic-version", .value = ANTHROPIC_VERSION },
        },
    });
    defer http_req.deinit();

    try http_req.sendBodyComplete(body);

    var redirect_buf: [1024]u8 = undefined;
    var response = try http_req.receiveHead(&redirect_buf);

    log.info("HTTP {d} encoding={s}", .{
        @intFromEnum(response.head.status),
        @tagName(response.head.content_encoding),
    });

    switch (response.head.content_encoding) {
        .compress, .zstd => {
            log.err("unsupported content-encoding: {s}", .{@tagName(response.head.content_encoding)});
            return error.UnsupportedCompressionMethod;
        },
        else => {},
    }

    var transfer_buf: [64 * 1024]u8 = undefined;
    var decompress: std.http.Decompress = undefined;
    const reader = response.readerDecompressing(&transfer_buf, &decompress, self.decompress_buf);

    if (response.head.status.class() != .success) {
        try handleHttpError(self, response.head.status, reader, ctx, onEvent);
        return error.HttpStatus;
    }

    var parser: sse.Parser = .{};
    defer parser.deinit(self.gpa);

    var arena: std.heap.ArenaAllocator = .init(self.gpa);
    defer arena.deinit();

    const Bridge = struct {
        ctx: @TypeOf(ctx),
        arena: *std.heap.ArenaAllocator,

        fn onSse(b: *@This(), raw: sse.Event) anyerror!void {
            _ = b.arena.reset(.retain_capacity);
            const decoded = try event.decode(b.arena.allocator(), raw);
            try onEvent(b.ctx, decoded);
        }
    };
    var bridge: Bridge = .{ .ctx = ctx, .arena = &arena };

    var lines: usize = 0;
    while (try reader.takeDelimiter('\n')) |line| {
        lines += 1;
        try parser.processLine(self.gpa, line, &bridge, Bridge.onSse);
    }
    log.info("stream finished, lines={d}", .{lines});
}

fn handleHttpError(
    self: *Client,
    status: std.http.Status,
    reader: anytype,
    ctx: anytype,
    comptime onEvent: fn (@TypeOf(ctx), event.StreamEvent) anyerror!void,
) !void {
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(self.gpa);

    var chunk: [4096]u8 = undefined;
    while (body.items.len < 64 * 1024) {
        const n = reader.readSliceShort(&chunk) catch |err| {
            log.err("anthropic {d}: failed reading error body: {}", .{ @intFromEnum(status), err });
            break;
        };
        if (n == 0) break;
        try body.appendSlice(self.gpa, chunk[0..n]);
        if (n < chunk.len) break;
    }

    log.err("anthropic returned HTTP {d}: {s}", .{ @intFromEnum(status), body.items });

    var arena: std.heap.ArenaAllocator = .init(self.gpa);
    defer arena.deinit();

    const message: []const u8 = blk: {
        const parsed = std.json.parseFromSliceLeaky(
            event.ErrorPayload,
            arena.allocator(),
            body.items,
            .{ .ignore_unknown_fields = true },
        ) catch break :blk body.items;
        break :blk parsed.@"error".message;
    };

    onEvent(ctx, .{ .err = .{ .@"error" = .{
        .type = @tagName(status.class()),
        .message = message,
    } } }) catch |err| log.err("postEvent for http error failed: {}", .{err});
}

test "MessageRequest serializes to expected JSON" {
    const t = std.testing;
    const messages = [_]Message{
        .{ .role = .user, .content = "hi" },
    };
    const body = try std.json.Stringify.valueAlloc(t.allocator, MessageRequest{
        .model = "claude-haiku-4-5-20251001",
        .max_tokens = 256,
        .messages = &messages,
    }, .{ .emit_null_optional_fields = false });
    defer t.allocator.free(body);

    try t.expectEqualStrings(
        \\{"model":"claude-haiku-4-5-20251001","max_tokens":256,"messages":[{"role":"user","content":"hi"}],"stream":true}
    , body);
}

test "MessageRequest with thinking serializes the thinking block" {
    const t = std.testing;
    const messages = [_]Message{
        .{ .role = .user, .content = "hi" },
    };
    const body = try std.json.Stringify.valueAlloc(t.allocator, MessageRequest{
        .model = "claude-haiku-4-5-20251001",
        .max_tokens = 4096,
        .messages = &messages,
        .thinking = .{},
    }, .{ .emit_null_optional_fields = false });
    defer t.allocator.free(body);

    try t.expectEqualStrings(
        \\{"model":"claude-haiku-4-5-20251001","max_tokens":4096,"messages":[{"role":"user","content":"hi"}],"stream":true,"thinking":{"type":"enabled","budget_tokens":2000}}
    , body);
}
