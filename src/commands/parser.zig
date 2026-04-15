const std = @import("std");

pub const ParsedInput = union(enum) {
    empty,
    text: []const u8,
    quit,
};

pub fn parse(line: []const u8) ParsedInput {
    const trimmed = std.mem.trim(u8, line, " \t\r\n");

    if (trimmed.len == 0) return .empty;
    if (std.mem.eql(u8, trimmed, "/quit")) return .quit;

    return .{ .text = trimmed };
}
