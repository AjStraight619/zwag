const std = @import("std");
const Allocator = std.mem.Allocator;
const vaxis = @import("vaxis");

const TextArea = @This();

gpa: Allocator,
buf: std.ArrayList(u8) = .empty,
cursor: usize = 0,
scroll_y: u16 = 0,

pub const Event = union(enum) {
    key_press: vaxis.Key,
};

pub fn init(gpa: Allocator) TextArea {
    return .{ .gpa = gpa };
}

pub fn deinit(self: *TextArea) void {
    self.buf.deinit(self.gpa);
}

pub fn update(self: *TextArea, event: Event) !void {
    switch (event) {
        .key_press => |key| try self.handleKey(key),
    }
}

pub fn insertSliceAtCursor(self: *TextArea, data: []const u8) !void {
    try self.buf.insertSlice(self.gpa, self.cursor, data);
    self.cursor += data.len;
}

pub fn toOwnedSlice(self: *TextArea) ![]u8 {
    const result = try self.buf.toOwnedSlice(self.gpa);
    self.cursor = 0;
    self.scroll_y = 0;
    return result;
}

pub fn clearAndFree(self: *TextArea) void {
    self.buf.clearAndFree(self.gpa);
    self.cursor = 0;
    self.scroll_y = 0;
}

pub fn desiredHeight(self: *const TextArea, width: u16, max: u16) u16 {
    if (width == 0) return 1;
    const total = self.totalRows(width);
    return @min(@max(total, 1), max);
}

pub fn draw(self: *TextArea, win: vaxis.Window) void {
    if (win.width == 0 or win.height == 0) return;

    const cursor_pos = self.cursorVisualPos(win.width);

    if (cursor_pos.row < self.scroll_y) self.scroll_y = cursor_pos.row;
    if (cursor_pos.row >= self.scroll_y + win.height) {
        self.scroll_y = cursor_pos.row + 1 - win.height;
    }

    var row: u16 = 0;
    var col: u16 = 0;
    var iter = vaxis.unicode.graphemeIterator(self.buf.items);
    while (iter.next()) |g| {
        const bytes = g.bytes(self.buf.items);
        if (std.mem.eql(u8, bytes, "\n")) {
            row += 1;
            col = 0;
            continue;
        }
        const w = vaxis.gwidth.gwidth(bytes, .unicode);
        if (col + w > win.width) {
            row += 1;
            col = 0;
        }
        if (row >= self.scroll_y and row < self.scroll_y + win.height) {
            win.writeCell(col, row - self.scroll_y, .{
                .char = .{ .grapheme = bytes, .width = @intCast(w) },
            });
        }
        col += w;
    }

    if (cursor_pos.row >= self.scroll_y and cursor_pos.row < self.scroll_y + win.height) {
        win.showCursor(cursor_pos.col, cursor_pos.row - self.scroll_y);
    }
}

fn handleKey(self: *TextArea, key: vaxis.Key) !void {
    if (key.matches(vaxis.Key.backspace, .{})) return self.deleteBefore();
    if (key.matches(vaxis.Key.delete, .{}) or key.matches('d', .{ .ctrl = true })) return self.deleteAt();
    if (key.matches(vaxis.Key.left, .{}) or key.matches('b', .{ .ctrl = true })) return self.moveLeft();
    if (key.matches(vaxis.Key.right, .{}) or key.matches('f', .{ .ctrl = true })) return self.moveRight();
    if (key.matches(vaxis.Key.up, .{})) return self.moveUp();
    if (key.matches(vaxis.Key.down, .{})) return self.moveDown();
    if (key.matches(vaxis.Key.home, .{}) or key.matches('a', .{ .ctrl = true })) {
        self.cursor = lineStart(self.buf.items, self.cursor);
        return;
    }
    if (key.matches(vaxis.Key.end, .{}) or key.matches('e', .{ .ctrl = true })) {
        self.cursor = lineEnd(self.buf.items, self.cursor);
        return;
    }

    if (key.text) |text| {
        try self.insertSliceAtCursor(text);
    }
}

fn moveLeft(self: *TextArea) void {
    if (self.cursor == 0) return;
    self.cursor = graphemeBoundaryBefore(self.buf.items, self.cursor);
}

fn moveRight(self: *TextArea) void {
    if (self.cursor >= self.buf.items.len) return;
    var iter = vaxis.unicode.graphemeIterator(self.buf.items[self.cursor..]);
    if (iter.next()) |g| self.cursor += g.start + g.len;
}

fn moveUp(self: *TextArea) void {
    const cur_start = lineStart(self.buf.items, self.cursor);
    if (cur_start == 0) return;
    const col_in_line = self.cursor - cur_start;
    const prev_end = cur_start - 1;
    const prev_start = lineStart(self.buf.items, prev_end);
    const prev_len = prev_end - prev_start;
    self.cursor = prev_start + @min(col_in_line, prev_len);
}

fn moveDown(self: *TextArea) void {
    const cur_start = lineStart(self.buf.items, self.cursor);
    const cur_end = lineEnd(self.buf.items, self.cursor);
    if (cur_end >= self.buf.items.len) return;
    const col_in_line = self.cursor - cur_start;
    const next_start = cur_end + 1;
    const next_end = lineEnd(self.buf.items, next_start);
    const next_len = next_end - next_start;
    self.cursor = next_start + @min(col_in_line, next_len);
}

fn deleteBefore(self: *TextArea) void {
    if (self.cursor == 0) return;
    const start = graphemeBoundaryBefore(self.buf.items, self.cursor);
    const removed = self.cursor - start;
    if (self.cursor < self.buf.items.len) {
        std.mem.copyForwards(
            u8,
            self.buf.items[start .. self.buf.items.len - removed],
            self.buf.items[self.cursor..],
        );
    }
    self.buf.shrinkRetainingCapacity(self.buf.items.len - removed);
    self.cursor = start;
}

fn deleteAt(self: *TextArea) void {
    if (self.cursor >= self.buf.items.len) return;
    var iter = vaxis.unicode.graphemeIterator(self.buf.items[self.cursor..]);
    const g = iter.next() orelse return;
    const removed = g.start + g.len;
    const end = self.cursor + removed;
    if (end < self.buf.items.len) {
        std.mem.copyForwards(
            u8,
            self.buf.items[self.cursor .. self.buf.items.len - removed],
            self.buf.items[end..],
        );
    }
    self.buf.shrinkRetainingCapacity(self.buf.items.len - removed);
}

const Pos = struct { row: u16, col: u16 };

fn cursorVisualPos(self: *const TextArea, width: u16) Pos {
    var row: u16 = 0;
    var col: u16 = 0;
    var iter = vaxis.unicode.graphemeIterator(self.buf.items);
    while (iter.next()) |g| {
        if (g.start >= self.cursor) break;
        const bytes = g.bytes(self.buf.items);
        if (std.mem.eql(u8, bytes, "\n")) {
            row += 1;
            col = 0;
            continue;
        }
        const w = vaxis.gwidth.gwidth(bytes, .unicode);
        if (col + w > width) {
            row += 1;
            col = 0;
        }
        col += w;
    }
    return .{ .row = row, .col = col };
}

fn totalRows(self: *const TextArea, width: u16) u16 {
    var row: u16 = 0;
    var col: u16 = 0;
    var iter = vaxis.unicode.graphemeIterator(self.buf.items);
    while (iter.next()) |g| {
        const bytes = g.bytes(self.buf.items);
        if (std.mem.eql(u8, bytes, "\n")) {
            row += 1;
            col = 0;
            continue;
        }
        const w = vaxis.gwidth.gwidth(bytes, .unicode);
        if (col + w > width) {
            row += 1;
            col = 0;
        }
        col += w;
    }
    return row + 1;
}

fn graphemeBoundaryBefore(buf: []const u8, pos: usize) usize {
    var iter = vaxis.unicode.graphemeIterator(buf[0..pos]);
    var last: usize = 0;
    while (iter.next()) |g| last = g.start;
    return last;
}

fn lineStart(buf: []const u8, pos: usize) usize {
    var i = pos;
    while (i > 0 and buf[i - 1] != '\n') i -= 1;
    return i;
}

fn lineEnd(buf: []const u8, pos: usize) usize {
    var i = pos;
    while (i < buf.len and buf[i] != '\n') i += 1;
    return i;
}
