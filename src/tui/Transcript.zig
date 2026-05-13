const std = @import("std");
const vaxis = @import("vaxis");
const Conversation = @import("../conversation/Conversation.zig");
const theme = @import("../theme.zig");

const Transcript = @This();

gpa: std.mem.Allocator,
view: ?vaxis.widgets.View = null,
scroll_y: usize = 0,
auto_scroll: bool = true,

pub fn deinit(self: *Transcript) void {
    if (self.view) |*v| v.deinit();
}

pub fn pageUp(self: *Transcript) void {
    self.scroll_y -|= 32;
    self.auto_scroll = false;
}

pub fn pageDown(self: *Transcript) void {
    self.scroll_y +|= 32;
    self.auto_scroll = false;
}

pub fn snapToBottom(self: *Transcript) void {
    self.auto_scroll = true;
}

pub fn render(
    self: *Transcript,
    body: vaxis.Window,
    messages: []const Conversation.Message,
    status_label: ?[]const u8,
) !void {
    if (messages.len == 0 and status_label == null) return;
    if (body.width == 0) return;

    var content_h: u16 = 0;
    for (messages, 0..) |msg, i| {
        if (i > 0) content_h += 1;
        content_h += measureHeight(body, msg.content.items);
    }

    const status_row_h: u16 = if (status_label != null) 1 else 0;
    const sep_before_status: u16 = if (status_label != null and content_h > 0) 1 else 0;
    const total_h = content_h + sep_before_status + status_row_h;
    if (total_h == 0) return;

    try self.ensureView(body.width, total_h);
    const view = &self.view.?;
    const view_win = view.window();
    view_win.clear();

    var y: u16 = 0;
    for (messages, 0..) |msg, i| {
        if (i > 0) y += 1;
        const h = measureHeight(view_win, msg.content.items);
        const msg_win = view_win.child(.{
            .x_off = 0,
            .y_off = @intCast(y),
            .width = view_win.width,
            .height = h,
        });
        const style: vaxis.Style = if (msg.role == .user)
            .{ .bg = theme.user_bg }
        else
            .{};
        if (msg.role == .user) {
            msg_win.fill(.{ .char = .{ .grapheme = " ", .width = 1 }, .style = style });
        }
        _ = msg_win.printSegment(.{ .text = msg.content.items, .style = style }, .{ .wrap = .grapheme });
        y += h;
    }

    if (status_label) |label| {
        if (content_h > 0) y += 1;
        const status_win = view_win.child(.{
            .x_off = 0,
            .y_off = @intCast(y),
            .width = view_win.width,
            .height = 1,
        });
        _ = status_win.printSegment(.{
            .text = label,
            .style = .{ .fg = theme.accent_dim },
        }, .{});
    }

    const max_scroll: usize = if (total_h > body.height) total_h - body.height else 0;
    if (self.auto_scroll) self.scroll_y = max_scroll;
    self.scroll_y = @min(self.scroll_y, max_scroll);
    // Re-arm auto_scroll once the user scrolls back to the bottom.
    if (self.scroll_y >= max_scroll) self.auto_scroll = true;

    view.draw(body, .{ .y_off = @intCast(self.scroll_y) });
}

fn ensureView(self: *Transcript, width: u16, height: u16) !void {
    if (self.view) |*v| {
        if (v.screen.width == width and v.screen.height >= height and v.screen.height <= height *| 2) return;
        v.deinit();
        self.view = null;
    }
    self.view = try vaxis.widgets.View.init(self.gpa, .{ .width = width, .height = height });
}

fn measureHeight(window: vaxis.Window, text: []const u8) u16 {
    const measured = window.printSegment(.{ .text = text }, .{
        .wrap = .grapheme,
        .commit = false,
    });
    return measured.row + 1;
}
