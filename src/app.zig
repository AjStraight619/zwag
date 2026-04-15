const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const FileReader = Io.File.Reader;
const FileWriter = Io.File.Writer;

const parser = @import("commands/parser.zig");

const App = @This();

gpa: Allocator,
io: Io,
should_quit: bool = false,

pub fn init(gpa: Allocator, io: Io) App {
    return .{
        .gpa = gpa,
        .io = io,
    };
}

pub fn run(self: *App) !void {
    var stdin_buf: [4096]u8 = undefined;
    var stdout_buf: [4096]u8 = undefined;

    var stdin_reader: FileReader = .init(.stdin(), self.io, &stdin_buf);
    var stdout_writer: FileWriter = .init(.stdout(), self.io, &stdout_buf);

    const reader = &stdin_reader.interface;
    const writer = &stdout_writer.interface;

    while (!self.should_quit) {
        try writer.writeAll("> ");
        try writer.flush();

        const maybe_line = try reader.takeDelimiter('\n');
        const line = maybe_line orelse {
            self.should_quit = true;
            break;
        };

        const parsed = parser.parse(line);
        try self.handleParsed(parsed, writer);
    }

    try writer.flush();
}

fn handleParsed(
    self: *App,
    parsed: parser.ParsedInput,
    writer: *Io.Writer,
) !void {
    switch (parsed) {
        .empty => {},
        .quit => self.should_quit = true,
        .text => |text| {
            try writer.print("text: {s}\n", .{text});
            try writer.flush();
        },
    }
}
