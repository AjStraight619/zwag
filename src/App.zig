const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const vaxis = @import("vaxis");

const Loop = @import("tui/Loop.zig");
const Event = Loop.Event;
const Conversation = @import("conversation/Conversation.zig");
const TextArea = @import("tui/TextArea.zig");
const CommandPicker = @import("tui/CommandPicker.zig");
const Transcript = @import("tui/Transcript.zig");
const Stream = @import("agent/Stream.zig");
const slash = @import("tui/slash.zig");
const theme = @import("theme.zig");

const log = std.log.scoped(.ui);

const App = @This();

pub const Mode = enum { normal, picker };

gpa: Allocator,
io: Io,
tty: *vaxis.Tty,
vx: *vaxis.Vaxis,
loop: *Loop,
stream: Stream,

input: TextArea,
conversation: Conversation,

mode: Mode = .normal,
picker: CommandPicker,

transcript: Transcript,

should_exit: bool = false,

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
        .stream = try Stream.init(gpa, io, loop, api_key),
        .input = .init(gpa),
        .conversation = .init(gpa),
        .picker = try CommandPicker.init(gpa, &CommandPicker.builtins),
        .transcript = .{ .gpa = gpa },
    };
}

pub fn deinit(self: *App) void {
    self.stream.deinit();
    self.input.deinit();
    self.picker.deinit();
    self.conversation.deinit();
    self.transcript.deinit();
}

pub fn run(self: *App) !void {
    while (true) {
        const ev = try self.loop.nextEvent();
        try self.handle(ev);
        if (self.should_exit) return;
        try self.render();
    }
}

fn handle(self: *App, event: Event) !void {
    defer Loop.freeOwned(self.gpa, event);
    self.stream.dispatch(event);
    switch (event) {
        .key_press => |key| {
            log.debug("key cp={d} shift={} ctrl={} alt={} text={?s}", .{
                key.codepoint, key.mods.shift, key.mods.ctrl, key.mods.alt, key.text,
            });
            if (key.matches('c', .{ .ctrl = true })) {
                self.should_exit = true;
                return;
            }
            if (key.matches(vaxis.Key.page_up, .{})) {
                self.transcript.pageUp();
                return;
            }
            if (key.matches(vaxis.Key.page_down, .{})) {
                self.transcript.pageDown();
                return;
            }

            if (self.mode == .picker) {
                if (key.matches(vaxis.Key.up, .{})) {
                    self.picker.moveUp();
                    return;
                }
                if (key.matches(vaxis.Key.down, .{})) {
                    self.picker.moveDown();
                    return;
                }
                if (key.matches(vaxis.Key.escape, .{})) {
                    self.input.clearAndFree();
                    try self.refreshMode();
                    return;
                }
                if (key.matches(vaxis.Key.enter, .{})) {
                    if (self.picker.current()) |cmd| {
                        if (slash.parse(cmd.name)) |sc| {
                            self.input.clearAndFree();
                            try self.refreshMode();
                            try slash.dispatch(self, sc);
                        } else {
                            try self.completePick(cmd);
                        }
                    }
                    return;
                }
            }

            if (key.matches(vaxis.Key.enter, .{ .shift = true }) or
                key.matches(vaxis.Key.enter, .{ .alt = true }))
            {
                try self.input.insertSliceAtCursor("\n");
                try self.refreshMode();
                return;
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
            try self.ensureAssistant();
            try self.conversation.appendToken(text);
        },
        .thinking_start, .thinking_end => {},
        .err => |msg| {
            log.err("event: {s}", .{msg});
            try self.ensureAssistant();
            self.conversation.appendToken("[error] ") catch {};
            self.conversation.appendToken(msg) catch {};
        },
        .stream_done => log.info("stream done", .{}),
    }
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
    if (self.stream.isActive()) return;

    const text = try self.input.toOwnedSlice();
    defer self.gpa.free(text);
    if (text.len == 0) return;

    const trimmed = std.mem.trim(u8, text, " \t\n");

    if (slash.parse(trimmed)) |cmd| {
        try slash.dispatch(self, cmd);
        return;
    }
    if (trimmed.len > 0 and trimmed[0] == '/') {
        const note = try std.fmt.allocPrint(self.gpa, "unknown command: {s}", .{trimmed});
        defer self.gpa.free(note);
        try self.conversation.appendMessage(.system, note);
        self.transcript.snapToBottom();
        return;
    }

    log.info("submit (len={d}) thinking_enabled=true", .{text.len});
    try self.conversation.appendMessage(.user, text);
    self.transcript.snapToBottom();

    try self.stream.start(self.conversation.messages.items);
}

fn ensureAssistant(self: *App) !void {
    const msgs = self.conversation.messages.items;
    if (msgs.len == 0 or msgs[msgs.len - 1].role != .assistant) {
        try self.conversation.beginAssistant();
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
    const status_label: ?[]const u8 = switch (self.stream.phase) {
        .idle, .responding => null,
        .thinking => "thinking…",
    };
    try self.transcript.render(body, self.conversation.messages.items, status_label);

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
