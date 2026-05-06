const std = @import("std");
const Allocator = std.mem.Allocator;
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const App = @This();

gpa: Allocator,
text_field: vxfw.TextField,

pub fn init(gpa: Allocator) !App {
    return .{
        .gpa = gpa,
        .text_field = vxfw.TextField.init(gpa),
    };
}

pub fn deinit(self: *App) void {
    self.text_field.deinit();
}

pub fn widget(self: *App) vxfw.Widget {
    self.text_field.userdata = self;
    self.text_field.onSubmit = onSubmit;
    return .{
        .userdata = self,
        .eventHandler = onEvent,
        .drawFn = onDraw,
    };
}

fn onEvent(ptr: *anyopaque, ctx: *vxfw.EventContext, ev: vxfw.Event) anyerror!void {
    const self: *App = @ptrCast(@alignCast(ptr));
    switch (ev) {
        .init, .focus_in => return ctx.requestFocus(self.text_field.widget()),
        .key_press => |k| {
            if (k.matches('c', .{ .ctrl = true })) ctx.quit = true;
        },
        else => {},
    }
}

fn onSubmit(maybe_ptr: ?*anyopaque, ctx: *vxfw.EventContext, text: []const u8) anyerror!void {
    const ptr = maybe_ptr orelse return;
    const self: *App = @ptrCast(@alignCast(ptr));

    // TODO: http req here, switch on event types. Prob SSE, maybe WS not sure.
    _ = text;
    self.text_field.buf.clearAndFree();
    ctx.consumeAndRedraw();
}

fn onDraw(ptr: *anyopaque, ctx: vxfw.DrawContext) Allocator.Error!vxfw.Surface {
    const self: *App = @ptrCast(@alignCast(ptr));
    const max = ctx.max.size();

    const input: vxfw.SubSurface = .{
        .origin = .{ .row = max.height - 1, .col = 0 },
        .surface = try self.text_field.widget().draw(
            ctx.withConstraints(ctx.min, .{ .width = max.width, .height = 1 }),
        ),
    };

    const children = try ctx.arena.alloc(vxfw.SubSurface, 1);
    children[0] = input;

    return .{
        .size = max,
        .widget = self.widget(),
        .buffer = &.{},
        .children = children,
    };
}
