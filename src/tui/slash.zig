//! Slash command parser. Pure data + parse — no side effects, no App import.
//! App.handleSlash dispatches the resulting Command.

const std = @import("std");
const CommandPicker = @import("CommandPicker.zig");

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

/// Picker-shaped view of `all`, suitable to hand to CommandPicker.init.
pub const picker_view: [all.len]CommandPicker.Command = blk: {
    var arr: [all.len]CommandPicker.Command = undefined;
    for (all, 0..) |spec, i| arr[i] = .{ .name = spec.name, .desc = spec.desc };
    break :blk arr;
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
