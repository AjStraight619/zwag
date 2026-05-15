//! Slash command parser and dispatcher for the TUI input box.
//! Intercepts `/foo` typed at the prompt before it reaches the API.

const std = @import("std");
const App = @import("../App.zig");

pub const Command = union(enum) {
    help,
    quit,
    clear,
};

pub const Spec = struct {
    name: []const u8,
    desc: []const u8,
    tag: Command,
};

/// Single source of truth — picker UI and parser both read from here.
pub const all = [_]Spec{
    .{ .name = "/help", .desc = "Show available commands", .tag = .help },
    .{ .name = "/clear", .desc = "Reset the conversation", .tag = .clear },
    .{ .name = "/quit", .desc = "Exit zwag", .tag = .quit },
};

pub fn parse(text: []const u8) ?Command {
    if (text.len == 0 or text[0] != '/') return null;
    const after_slash = text[1..];
    const end = std.mem.indexOfAny(u8, after_slash, " \t\n") orelse after_slash.len;
    const name = after_slash[0..end];

    for (all) |spec| {
        if (std.ascii.eqlIgnoreCase(spec.name[1..], name)) return spec.tag;
    }
    return null;
}

pub fn dispatch(app: *App, cmd: Command) !void {
    switch (cmd) {
        .quit => app.should_exit = true,
        .help => try runHelp(app),
        .clear => try runClear(app),
    }
}

fn runHelp(app: *App) !void {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(app.gpa);

    var max_name: usize = 0;
    for (all) |spec| {
        if (spec.name.len > max_name) max_name = spec.name.len;
    }

    try buf.appendSlice(app.gpa, "Available commands:\n");
    for (all) |spec| {
        try buf.appendSlice(app.gpa, "  ");
        try buf.appendSlice(app.gpa, spec.name);
        for (spec.name.len..max_name + 2) |_| try buf.append(app.gpa, ' ');
        try buf.appendSlice(app.gpa, spec.desc);
        try buf.append(app.gpa, '\n');
    }
    try buf.appendSlice(app.gpa, "\nShift+Enter or Alt+Enter inserts a newline. Enter submits.");

    try app.conversation.appendMessage(.system, buf.items);
    app.transcript.snapToBottom();
}

fn runClear(app: *App) !void {
    app.conversation.deinit();
    app.conversation = .init(app.gpa);
    app.transcript.snapToBottom();
}

test "parse recognizes built-in commands" {
    const t = std.testing;
    try t.expectEqual(Command.help, parse("/help").?);
    try t.expectEqual(Command.quit, parse("/quit").?);
    try t.expectEqual(Command.clear, parse("/clear").?);
}

test "parse ignores trailing args" {
    const t = std.testing;
    try t.expectEqual(Command.help, parse("/help arg").?);
    try t.expectEqual(Command.help, parse("/help\textra").?);
}

test "parse is case-insensitive" {
    const t = std.testing;
    try t.expectEqual(Command.help, parse("/Help").?);
    try t.expectEqual(Command.help, parse("/HELP").?);
    try t.expectEqual(Command.quit, parse("/QuIt").?);
}

test "parse returns null for non-slash and unknown" {
    const t = std.testing;
    try t.expectEqual(@as(?Command, null), parse(""));
    try t.expectEqual(@as(?Command, null), parse("hello"));
    try t.expectEqual(@as(?Command, null), parse("/foo"));
    try t.expectEqual(@as(?Command, null), parse("/"));
}
