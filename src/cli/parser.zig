const std = @import("std");
const mem = std.mem;

pub const Command = union(enum) {
    help,
    version,
};

pub const ParseError = error{UnknownCommand};

pub fn parse(args: []const [:0]const u8) ParseError!Command {
    std.debug.assert(args.len > 1);

    const first = args[1];
    if (mem.eql(u8, first, "--help") or mem.eql(u8, first, "-h")) return .help;
    if (mem.eql(u8, first, "--version") or mem.eql(u8, first, "-V")) return .version;
    return ParseError.UnknownCommand;
}
