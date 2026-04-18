const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Agent = @This();

// Inject tool based on mode
pub const Mode = enum {
    plan, // read only access and extra tools for planning
    implement,
};
