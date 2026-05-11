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

pub fn appendUser(self: *Conversation, text: []const u8) !void {
    var content: std.ArrayList(u8) = .empty;
    errdefer content.deinit(self.gpa);
    try content.appendSlice(self.gpa, text);
    try self.messages.append(self.gpa, .{ .role = .user, .content = content });
}

pub fn beginAssistant(self: *Conversation) !void {
    try self.messages.append(self.gpa, .{ .role = .assistant, .content = .empty });
}

pub fn appendToken(self: *Conversation, text: []const u8) !void {
    std.debug.assert(self.messages.items.len > 0);
    const last = &self.messages.items[self.messages.items.len - 1];
    std.debug.assert(last.role == .assistant);
    try last.content.appendSlice(self.gpa, text);
}

const Serialized = struct {
    messages: []const Message,
};

const Loaded = struct {
    messages: []Message,
};

/// Caller frees returned bytes.
pub fn toJsonAlloc(self: *const Conversation, gpa: Allocator) ![]u8 {
    // TODO: std.json.Stringify.valueAlloc(gpa, Serialized{ .messages = self.messages.items }, .{})
    _ = self;
    _ = gpa;
    return error.NotImplemented;
}

/// Returns a fully-owned Conversation. Bytes from `json` may be borrowed
/// during parse but the returned messages all own their content.
pub fn fromJson(gpa: Allocator, json: []const u8) !Conversation {
    // TODO: parse Loaded, dupe each content into self.gpa, append.
    _ = gpa;
    _ = json;
    return error.NotImplemented;
}
