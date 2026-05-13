const std = @import("std");
const Allocator = std.mem.Allocator;

const Conversation = @This();

pub const Role = enum { user, assistant, system };

pub const Message = struct {
    role: Role,
    content: std.ArrayList(u8),
};

gpa: Allocator,
messages: std.ArrayList(Message) = .empty,

pub fn init(gpa: Allocator) Conversation {
    return .{ .gpa = gpa };
}

pub fn deinit(self: *Conversation) void {
    for (self.messages.items) |*m| m.content.deinit(self.gpa);
    self.messages.deinit(self.gpa);
}

pub fn appendMessage(self: *Conversation, role: Role, text: []const u8) !void {
    var content: std.ArrayList(u8) = .empty;
    errdefer content.deinit(self.gpa);
    try content.appendSlice(self.gpa, text);
    try self.messages.append(self.gpa, .{ .role = role, .content = content });
}

pub fn beginAssistant(self: *Conversation) !void {
    try self.messages.append(self.gpa, .{ .role = .assistant, .content = .empty });
}

/// Mutates only the current (tail) assistant message; historic messages
/// stay byte-stable so in-flight stream snapshots can borrow them.
pub fn appendToken(self: *Conversation, text: []const u8) !void {
    std.debug.assert(self.messages.items.len > 0);
    const last = &self.messages.items[self.messages.items.len - 1];
    std.debug.assert(last.role == .assistant);
    try last.content.appendSlice(self.gpa, text);
}
