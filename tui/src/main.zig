const std = @import("std");

const App = @import("app.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io; // default backend chosen by Zig

    _ = App.init(gpa, io);
    // try app.run();
}
