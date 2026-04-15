const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Model = @This();

pub const InitError = error{
    EmptyModelName,
    EmptyURL,
    MissingAPIKey,
};

pub const CallError = error{
    MissingAPIKey,
    NotImplemented,
    RequestFailed,
    InvalidResponse,
};

pub const Provider = enum {
    openai,
    anthropic,
    ollama,
};

pub const Options = struct {
    api_key: ?[]const u8 = null,
    thinking: bool = false,
    stream: bool = false,
};

pub const Response = struct {
    id: ?[]const u8 = null,
    status: ?[]const u8 = null,
    output: []const OutputItem = &.{},

    pub const OutputItem = struct {
        type: []const u8,

        // message
        content: ?[]const ContentPart = null,

        // function_call
        call_id: ?[]const u8 = null,
        name: ?[]const u8 = null,
        arguments: ?[]const u8 = null,

        // reasoning
        summary: ?[]const SummaryPart = null,
    };

    pub const ContentPart = struct {
        type: []const u8,
        text: ?[]const u8 = null,
    };

    pub const SummaryPart = struct {
        type: []const u8,
        text: []const u8,
    };

    pub const ToolCall = struct {
        call_id: []const u8,
        name: []const u8,
        arguments_json: []const u8,
    };

    pub fn text(self: Response) ?[]const u8 {
        for (self.output) |item| {
            if (!std.mem.eql(u8, item.type, "message")) continue;
            const content = item.content orelse continue;

            for (content) |part| {
                if (std.mem.eql(u8, part.type, "output_text")) {
                    if (part.text) |part_text| return part_text;
                }
            }
        }

        return null;
    }

    pub fn thinking(self: Response) ?[]const u8 {
        for (self.output) |item| {
            if (!std.mem.eql(u8, item.type, "reasoning")) continue;
            const summary = item.summary orelse continue;

            for (summary) |part| {
                if (std.mem.eql(u8, part.type, "summary_text")) {
                    return part.text;
                }
            }
        }

        return null;
    }

    pub fn firstToolCall(self: Response) ?ToolCall {
        for (self.output) |item| {
            if (!std.mem.eql(u8, item.type, "function_call")) continue;

            return .{
                .call_id = item.call_id orelse continue,
                .name = item.name orelse continue,
                .arguments_json = item.arguments orelse continue,
            };
        }

        return null;
    }
};

gpa: Allocator,
io: Io,
provider: Provider,
name: []const u8,
url: []const u8,
options: Options,

pub fn init(
    gpa: Allocator,
    io: Io,
    provider: Provider,
    name: []const u8,
    url: []const u8,
    opts: Options,
) InitError!Model {
    if (name.len == 0) return error.EmptyModelName;
    if (url.len == 0) return error.EmptyURL;

    switch (provider) {
        .openai => {
            if (opts.api_key == null) return error.MissingAPIKey;
        },
        .anthropic, .ollama => {},
    }

    return .{
        .gpa = gpa,
        .io = io,
        .provider = provider,
        .name = name,
        .url = url,
        .options = opts,
    };
}

pub fn call(self: *const Model, query: []const u8) CallError!Response {
    return switch (self.provider) {
        .openai => self.callOpenAI(query),
        .anthropic, .ollama => error.NotImplemented,
    };
}

fn callOpenAI(self: *const Model, query: []const u8) CallError!Response {
    _ = self;
    _ = query;

    // HTTP later
    return error.NotImplemented;
}
