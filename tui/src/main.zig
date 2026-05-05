const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const App = @import("app.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var buffer: [1024]u8 = undefined;
    var rt: vxfw.App = try .init(init.io, gpa, init.environ_map, &buffer);
    defer rt.deinit();

    const app = try gpa.create(App);
    defer gpa.destroy(app);
    app.* = try App.init(gpa);
    defer app.deinit();

    try rt.run(app.widget(), .{});
}
