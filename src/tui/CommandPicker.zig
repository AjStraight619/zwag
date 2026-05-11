const std = @import("std");
const Allocator = std.mem.Allocator;
const vaxis = @import("vaxis");

const theme = @import("../theme.zig");

const CommandPicker = @This();

pub const Command = struct {
    name: []const u8,
    desc: []const u8,
};

pub const builtins = [_]Command{
    .{ .name = "/help", .desc = "Show available commands" },
    .{ .name = "/clear", .desc = "Clear the conversation transcript" },
    .{ .name = "/provider", .desc = "Switch LLM provider (openai|anthropic|ollama)" },
    .{ .name = "/model", .desc = "Switch the active model" },
    .{ .name = "/compact", .desc = "Compact the context window via summary" },
    .{ .name = "/history", .desc = "Browse past sessions" },
    .{ .name = "/export", .desc = "Export the current transcript" },
    .{ .name = "/tools", .desc = "List available tools" },
    .{ .name = "/cost", .desc = "Show token usage and cost" },
    .{ .name = "/quit", .desc = "Exit zwag" },
};

gpa: Allocator,
all: []const Command,
filtered: std.ArrayList(usize) = .empty,
selected: usize = 0,

pub fn init(gpa: Allocator, all: []const Command) !CommandPicker {
    var p: CommandPicker = .{ .gpa = gpa, .all = all };
    try p.setFilter("");
    return p;
}

pub fn deinit(self: *CommandPicker) void {
    self.filtered.deinit(self.gpa);
}

pub fn setFilter(self: *CommandPicker, filter: []const u8) !void {
    self.filtered.clearRetainingCapacity();

    for (self.all, 0..) |cmd, i| {
        const name = cmd.name[1..];
        if (filter.len == 0 or std.ascii.indexOfIgnoreCase(name, filter) != null) {
            try self.filtered.append(self.gpa, i);
        }
    }

    const ctx = SortCtx{ .all = self.all, .filter = filter };
    std.mem.sort(usize, self.filtered.items, ctx, SortCtx.lessThan);

    if (self.selected >= self.filtered.items.len) self.selected = 0;
}

const SortCtx = struct {
    all: []const Command,
    filter: []const u8,

    fn lessThan(ctx: SortCtx, a: usize, b: usize) bool {
        const a_name = ctx.all[a].name[1..];
        const b_name = ctx.all[b].name[1..];
        if (ctx.filter.len > 0) {
            const a_pos = std.ascii.indexOfIgnoreCase(a_name, ctx.filter) orelse std.math.maxInt(usize);
            const b_pos = std.ascii.indexOfIgnoreCase(b_name, ctx.filter) orelse std.math.maxInt(usize);
            if (a_pos != b_pos) return a_pos < b_pos;
        }
        return std.mem.lessThan(u8, a_name, b_name);
    }
};

pub fn moveUp(self: *CommandPicker) void {
    if (self.filtered.items.len == 0) return;
    self.selected = if (self.selected == 0) self.filtered.items.len - 1 else self.selected - 1;
}

pub fn moveDown(self: *CommandPicker) void {
    if (self.filtered.items.len == 0) return;
    self.selected = (self.selected + 1) % self.filtered.items.len;
}

pub fn current(self: *const CommandPicker) ?Command {
    if (self.filtered.items.len == 0) return null;
    return self.all[self.filtered.items[self.selected]];
}

pub fn desiredHeight(self: *const CommandPicker, max: u16) u16 {
    const n: u16 = @intCast(self.filtered.items.len);
    return @min(@max(n, 1), max);
}

pub fn draw(self: *const CommandPicker, win: vaxis.Window) void {
    if (win.width == 0 or win.height == 0) return;

    if (self.filtered.items.len == 0) {
        _ = win.printSegment(.{
            .text = "no matches",
            .style = .{ .fg = theme.text_dim },
        }, .{});
        return;
    }

    var name_w: u16 = 0;
    for (self.filtered.items) |idx| {
        const w: u16 = @intCast(vaxis.gwidth.gwidth(self.all[idx].name, .unicode));
        if (w > name_w) name_w = w;
    }
    const desc_x: u16 = name_w + 4;

    var row: u16 = 0;
    for (self.filtered.items, 0..) |idx, i| {
        if (row >= win.height) break;
        const cmd = self.all[idx];
        const is_selected = i == self.selected;

        const row_style: vaxis.Style = if (is_selected)
            .{ .bg = theme.selection_bg, .fg = theme.accent }
        else
            .{};
        const desc_style: vaxis.Style = if (is_selected)
            .{ .bg = theme.selection_bg, .fg = theme.accent_dim }
        else
            .{ .fg = theme.text_dim };

        const row_win = win.child(.{
            .x_off = 0,
            .y_off = row,
            .width = win.width,
            .height = 1,
        });
        if (is_selected) {
            row_win.fill(.{
                .char = .{ .grapheme = " ", .width = 1 },
                .style = .{ .bg = theme.selection_bg },
            });
        }

        const marker = if (is_selected) "▸ " else "  ";
        _ = row_win.printSegment(.{ .text = marker, .style = row_style }, .{});

        const name_win = row_win.child(.{
            .x_off = 2,
            .y_off = 0,
            .width = win.width -| 2,
            .height = 1,
        });
        _ = name_win.printSegment(.{ .text = cmd.name, .style = row_style }, .{});

        if (desc_x + 1 < win.width) {
            const desc_win = row_win.child(.{
                .x_off = desc_x,
                .y_off = 0,
                .width = win.width -| desc_x,
                .height = 1,
            });
            _ = desc_win.printSegment(.{ .text = cmd.desc, .style = desc_style }, .{});
        }

        row += 1;
    }
}
