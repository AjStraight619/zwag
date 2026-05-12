pub const Provider = enum {
    anthropic,

    pub fn envKey(self: Provider) ?[]const u8 {
        return switch (self) {
            .anthropic => "ANTHROPIC_API_KEY",
        };
    }
};
