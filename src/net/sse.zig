const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Event = struct {
    name: []const u8,
    data: []const u8,
};

pub const Parser = struct {
    name: std.ArrayList(u8) = .empty,
    data: std.ArrayList(u8) = .empty,

    pub fn deinit(self: *Parser, gpa: Allocator) void {
        self.name.deinit(gpa);
        self.data.deinit(gpa);
    }

    pub fn processLine(
        self: *Parser,
        gpa: Allocator,
        raw_line: []const u8,
        ctx: anytype,
        comptime onEvent: fn (@TypeOf(ctx), Event) anyerror!void,
    ) !void {
        const line = if (raw_line.len > 0 and raw_line[raw_line.len - 1] == '\r')
            raw_line[0 .. raw_line.len - 1]
        else
            raw_line;

        if (line.len == 0) {
            if (self.name.items.len == 0 and self.data.items.len == 0) return;
            try onEvent(ctx, .{ .name = self.name.items, .data = self.data.items });
            self.name.clearRetainingCapacity();
            self.data.clearRetainingCapacity();
            return;
        }
        if (line[0] == ':') return;

        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return;
        const field = line[0..colon];
        var value = line[colon + 1 ..];
        if (value.len > 0 and value[0] == ' ') value = value[1..];

        if (std.mem.eql(u8, field, "event")) {
            self.name.clearRetainingCapacity();
            try self.name.appendSlice(gpa, value);
        } else if (std.mem.eql(u8, field, "data")) {
            if (self.data.items.len > 0) try self.data.append(gpa, '\n');
            try self.data.appendSlice(gpa, value);
        }
    }
};

test "single event via line-by-line feed" {
    const t = std.testing;
    var p: Parser = .{};
    defer p.deinit(t.allocator);

    var saw: ?struct { name: []u8, data: []u8 } = null;
    defer if (saw) |s| {
        t.allocator.free(s.name);
        t.allocator.free(s.data);
    };

    const Cb = struct {
        fn cb(out: *@TypeOf(saw), ev: Event) !void {
            out.* = .{
                .name = try t.allocator.dupe(u8, ev.name),
                .data = try t.allocator.dupe(u8, ev.data),
            };
        }
    };

    try p.processLine(t.allocator, "event: token", &saw, Cb.cb);
    try p.processLine(t.allocator, "data: {\"content\":\"hi\"}", &saw, Cb.cb);
    try p.processLine(t.allocator, "", &saw, Cb.cb);

    try t.expect(saw != null);
    try t.expectEqualStrings("token", saw.?.name);
    try t.expectEqualStrings("{\"content\":\"hi\"}", saw.?.data);
}

test "multi-line data joins with newline" {
    const t = std.testing;
    var p: Parser = .{};
    defer p.deinit(t.allocator);

    const Counter = struct {
        n: usize = 0,
        last_data: [128]u8 = undefined,
        last_data_len: usize = 0,

        fn cb(self: *@This(), ev: Event) !void {
            self.n += 1;
            @memcpy(self.last_data[0..ev.data.len], ev.data);
            self.last_data_len = ev.data.len;
        }
    };
    var c: Counter = .{};

    try p.processLine(t.allocator, "event: tool_call", &c, Counter.cb);
    try p.processLine(t.allocator, "data: line1", &c, Counter.cb);
    try p.processLine(t.allocator, "data: line2", &c, Counter.cb);
    try p.processLine(t.allocator, "", &c, Counter.cb);

    try t.expectEqual(@as(usize, 1), c.n);
    try t.expectEqualStrings("line1\nline2", c.last_data[0..c.last_data_len]);
}

test "trailing CR stripped" {
    const t = std.testing;
    var p: Parser = .{};
    defer p.deinit(t.allocator);

    var saw: ?Event = null;
    const Cb = struct {
        fn cb(out: *@TypeOf(saw), ev: Event) !void {
            out.* = ev;
        }
    };

    try p.processLine(t.allocator, "event: ping\r", &saw, Cb.cb);
    try p.processLine(t.allocator, "\r", &saw, Cb.cb);

    try t.expect(saw != null);
    try t.expectEqualStrings("ping", saw.?.name);
}
