const std = @import("std");
const Allocator = std.mem.Allocator;
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const App = @This();

gpa: std.mem.Allocator,

pub fn init(gpa: std.mem.Allocator) !App {
    return .{ .gpa = gpa };
}

pub fn deinit(self: *App) void {
    _ = self;
}

pub fn widget(self: *App) vxfw.Widget {
    return .{
        .userdata = self,
        .eventHandler = onEvent,
        .drawFn = onDraw,
    };
}

fn onEvent(ptr: *anyopaque, ctx: *vxfw.EventContext, ev: vxfw.Event) anyerror!void {
    const self: *App = @ptrCast(@alignCast(ptr));
    _ = self;
    switch (ev) {
        .key_press => |k| {
            if (k.matches('c', .{ .ctrl = true })) ctx.quit = true;
        },
        else => {},
    }
}

fn onDraw(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const self: *App = @ptrCast(@alignCast(ptr));
    const size = ctx.max.size();
    return .{
        .size = size,
        .widget = self.widget(),
        .buffer = &.{},
        .children = &.{},
    };
}
