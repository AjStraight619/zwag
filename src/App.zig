const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const vaxis = @import("vaxis");

const Client = @import("net/Client.zig");
const stream_event = @import("net/event.zig");
const Conversation = @import("conversation/Conversation.zig");
const TextArea = @import("tui/TextArea.zig");
const CommandPicker = @import("tui/CommandPicker.zig");
const theme = @import("theme.zig");

const log = std.log.scoped(.ui);

const App = @This();

pub const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    text_delta: []u8,
    thinking_start,
    thinking_end,
    err: []u8,
    stream_done,
};

pub const Loop = vaxis.Loop(Event);

pub const Mode = enum { normal, picker };

gpa: Allocator,
io: Io,
tty: *vaxis.Tty,
vx: *vaxis.Vaxis,
loop: *Loop,
client: Client,

input: TextArea,
conversation: Conversation,
in_flight: ?Io.Future(anyerror!void) = null,

mode: Mode = .normal,
picker: CommandPicker,

worker_in_thinking: bool = false,
assistant_thinking: bool = false,

transcript_view: ?vaxis.widgets.View = null,
scroll_y: usize = 0,
auto_scroll: bool = true,

pub fn init(
    gpa: Allocator,
    io: Io,
    tty: *vaxis.Tty,
    vx: *vaxis.Vaxis,
    loop: *Loop,
    api_key: []const u8,
) !App {
    return .{
        .gpa = gpa,
        .io = io,
        .tty = tty,
        .vx = vx,
        .loop = loop,
        .client = try Client.init(gpa, io, api_key, Client.DEFAULT_BASE_URL),
        .input = .init(gpa),
        .conversation = .init(gpa),
        .picker = try CommandPicker.init(gpa, &CommandPicker.builtins),
    };
}

pub fn deinit(self: *App) void {
    if (self.in_flight) |*f| f.cancel(self.io) catch {};
    self.input.deinit();
    self.picker.deinit();
    self.client.deinit();
    self.conversation.deinit();
    if (self.transcript_view) |*v| v.deinit();
}

pub fn run(self: *App) !void {
    while (true) {
        const ev = try self.loop.nextEvent();
        if (try self.handle(ev)) return;
        try self.render();
    }
}

fn handle(self: *App, event: Event) !bool {
    switch (event) {
        .key_press => |key| {
            log.debug("key cp={d} shift={} ctrl={} alt={} text={?s}", .{
                key.codepoint, key.mods.shift, key.mods.ctrl, key.mods.alt, key.text,
            });
            if (key.matches('c', .{ .ctrl = true })) return true;
            if (key.matches(vaxis.Key.page_up, .{})) {
                self.scroll_y -|= 32;
                self.auto_scroll = false;
                return false;
            }
            if (key.matches(vaxis.Key.page_down, .{})) {
                self.scroll_y +|= 32;
                self.auto_scroll = false;
                return false;
            }

            if (self.mode == .picker) {
                if (key.matches(vaxis.Key.up, .{})) {
                    self.picker.moveUp();
                    return false;
                }
                if (key.matches(vaxis.Key.down, .{})) {
                    self.picker.moveDown();
                    return false;
                }
                if (key.matches(vaxis.Key.escape, .{})) {
                    self.input.clearAndFree();
                    try self.refreshMode();
                    return false;
                }
                if (key.matches(vaxis.Key.enter, .{})) {
                    if (self.picker.current()) |cmd| try self.completePick(cmd);
                    return false;
                }
            }

            if (key.codepoint == '\n' or
                key.matches(vaxis.Key.enter, .{ .shift = true }) or
                key.matches(vaxis.Key.enter, .{ .alt = true }))
            {
                try self.input.insertSliceAtCursor("\n");
                try self.refreshMode();
                return false;
            }
            if (self.mode == .normal and key.matches(vaxis.Key.enter, .{})) {
                try self.submit();
            } else {
                try self.input.update(.{ .key_press = key });
                try self.refreshMode();
            }
        },
        .winsize => |ws| try self.vx.resize(self.gpa, self.tty.writer(), ws),
        .text_delta => |text| {
            defer self.gpa.free(text);
            try self.ensureAssistant();
            try self.conversation.appendToken(text);
        },
        .thinking_start => {
            log.info("main: thinking_start received → indicator on", .{});
            self.assistant_thinking = true;
        },
        .thinking_end => {
            log.info("main: thinking_end received → indicator off", .{});
            self.assistant_thinking = false;
        },
        .err => |msg| {
            defer self.gpa.free(msg);
            log.err("event: {s}", .{msg});
            try self.ensureAssistant();
            self.conversation.appendToken("[error] ") catch {};
            self.conversation.appendToken(msg) catch {};
        },
        .stream_done => {
            log.info("stream done", .{});
            self.assistant_thinking = false;
            if (self.in_flight) |*f| {
                f.await(self.io) catch |err| log.err("stream: {}", .{err});
                self.in_flight = null;
            }
        },
    }
    return false;
}

fn refreshMode(self: *App) !void {
    const buf = self.input.buf.items;
    const in_name = buf.len > 0 and buf[0] == '/' and std.mem.indexOfAny(u8, buf, " \t\n") == null;
    if (in_name) {
        self.mode = .picker;
        try self.picker.setFilter(buf[1..]);
    } else {
        self.mode = .normal;
    }
}

fn completePick(self: *App, cmd: CommandPicker.Command) !void {
    self.input.clearAndFree();
    try self.input.insertSliceAtCursor(cmd.name);
    try self.input.insertSliceAtCursor(" ");
    try self.refreshMode();
}

fn submit(self: *App) !void {
    if (self.in_flight != null) return;

    const text = try self.input.toOwnedSlice();
    defer self.gpa.free(text);
    if (text.len == 0) return;

    log.info("submit (len={d}) thinking_enabled=true", .{text.len});
    try self.conversation.appendUser(text);
    self.auto_scroll = true;

    const history = self.conversation.messages.items;
    self.in_flight = try self.io.concurrent(runStream, .{ self, history });
}

fn ensureAssistant(self: *App) !void {
    const msgs = self.conversation.messages.items;
    if (msgs.len == 0 or msgs[msgs.len - 1].role != .assistant) {
        try self.conversation.beginAssistant();
    }
}

fn postOwnedEvent(self: *App, comptime field: []const u8, text: []const u8) !void {
    const owned = try self.gpa.dupe(u8, text);
    errdefer self.gpa.free(owned);
    try self.loop.postEvent(@unionInit(Event, field, owned));
}

fn runStream(self: *App, history: []const Conversation.Message) anyerror!void {
    defer self.loop.postEvent(.stream_done) catch {};

    const api_messages = try self.gpa.alloc(Client.Message, history.len);
    defer self.gpa.free(api_messages);
    for (history, 0..) |m, i| {
        api_messages[i] = .{
            .role = switch (m.role) {
                .user => .user,
                .assistant => .assistant,
                .system => .assistant,
            },
            .content = m.content.items,
        };
    }

    const req: Client.MessageRequest = .{
        .model = "claude-haiku-4-5-20251001",
        .messages = api_messages,
        .thinking = .{},
    };

    self.client.streamMessages(req, self, onSse) catch |err| {
        self.postOwnedEvent("err", @errorName(err)) catch {};
        return err;
    };
}

fn onSse(self: *App, ev: stream_event.StreamEvent) anyerror!void {
    log.debug("sse event: {s}", .{@tagName(ev)});
    switch (ev) {
        .content_block_start => |b| {
            log.debug("content_block_start type={s}", .{b.content_block.type});
            if (std.mem.eql(u8, b.content_block.type, "thinking")) {
                log.info("worker: entering thinking block", .{});
                self.worker_in_thinking = true;
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
            if (self.worker_in_thinking) {
                log.info("worker: exiting thinking block", .{});
                self.worker_in_thinking = false;
                try self.loop.postEvent(.thinking_end);
            }
        },
        .err => |e| try self.postOwnedEvent("err", e.@"error".message),
        else => {},
    }
}

fn render(self: *App) !void {
    const win = self.vx.window();
    win.clear();

    const input_inner_w: u16 = win.width -| 2;
    const max_input_rows: u16 = @max(1, win.height / 3);
    const input_inner_h = self.input.desiredHeight(input_inner_w, max_input_rows);
    const input_box_h: u16 = input_inner_h + 2;

    const picker_box_h: u16 = if (self.mode == .picker)
        self.picker.desiredHeight(10) + 2
    else
        0;

    const body = win.child(.{
        .x_off = 1,
        .y_off = 0,
        .width = win.width -| 2,
        .height = win.height -| (input_box_h + picker_box_h + 1),
    });
    try self.renderTranscript(body);

    const input_box = win.child(.{
        .x_off = 0,
        .y_off = win.height -| (input_box_h + picker_box_h),
        .width = win.width,
        .height = input_box_h,
        .border = .{ .where = .all, .style = .{ .dim = true } },
    });
    self.input.draw(input_box);

    if (self.mode == .picker) {
        const picker_box = win.child(.{
            .x_off = 0,
            .y_off = win.height -| picker_box_h,
            .width = win.width,
            .height = picker_box_h,
            .border = .{ .where = .all, .style = .{ .fg = theme.accent_dim } },
        });
        self.picker.draw(picker_box);
    }

    try self.vx.render(self.tty.writer());
}

fn renderTranscript(self: *App, body: vaxis.Window) !void {
    const messages = self.conversation.messages.items;
    if (messages.len == 0 and !self.assistant_thinking) return;
    if (body.width == 0) return;

    var content_h: u16 = 0;
    for (messages, 0..) |msg, i| {
        if (i > 0) content_h += 1;
        content_h += measureHeight(body, msg.content.items);
    }

    const thinking_row_h: u16 = if (self.assistant_thinking) 1 else 0;
    const sep_before_thinking: u16 = if (self.assistant_thinking and content_h > 0) 1 else 0;
    const total_h = content_h + sep_before_thinking + thinking_row_h;
    if (total_h == 0) return;

    try self.ensureView(body.width, total_h);
    const view = &self.transcript_view.?;
    const view_win = view.window();
    view_win.clear();

    var y: u16 = 0;
    for (messages, 0..) |msg, i| {
        if (i > 0) y += 1;
        const h = measureHeight(view_win, msg.content.items);
        const msg_win = view_win.child(.{ .x_off = 0, .y_off = @intCast(y), .width = view_win.width, .height = h });
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

    if (self.assistant_thinking) {
        if (content_h > 0) y += 1;
        const status_win = view_win.child(.{
            .x_off = 0,
            .y_off = @intCast(y),
            .width = view_win.width,
            .height = 1,
        });
        _ = status_win.printSegment(.{
            .text = "thinking…",
            .style = .{ .fg = theme.accent_dim },
        }, .{});
    }

    const max_scroll: usize = if (total_h > body.height) total_h - body.height else 0;
    if (self.auto_scroll) self.scroll_y = max_scroll;
    self.scroll_y = @min(self.scroll_y, max_scroll);
    if (self.scroll_y >= max_scroll) self.auto_scroll = true;

    view.draw(body, .{ .y_off = @intCast(self.scroll_y) });
}

fn ensureView(self: *App, width: u16, height: u16) !void {
    if (self.transcript_view) |*v| {
        if (v.screen.width == width and v.screen.height >= height) return;
        v.deinit();
        self.transcript_view = null;
    }
    self.transcript_view = try vaxis.widgets.View.init(self.gpa, .{ .width = width, .height = height });
}

fn measureHeight(window: vaxis.Window, text: []const u8) u16 {
    const measured = window.printSegment(.{ .text = text }, .{
        .wrap = .grapheme,
        .commit = false,
    });
    return measured.row + 1;
}
