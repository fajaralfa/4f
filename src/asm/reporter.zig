const std = @import("std");

pub const MessageType = enum {
    Err,
    Warn,
    Info,
    Debug,
};

pub const Reporter = struct {
    errors: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    debug: bool,

    pub fn init(allocator: std.mem.Allocator, debug: bool) Reporter {
        return Reporter{
            .errors = std.ArrayList([]const u8).empty,
            .allocator = allocator,
            .debug = debug,
        };
    }

    pub fn deinit(self: *Reporter) void {
        for (self.errors.items) |s| {
            self.allocator.free(s);
        }
        self.errors.deinit(self.allocator);
    }

    pub fn add(self: *Reporter, rtype: MessageType, comptime message: []const u8, args: anytype) !void {
        _ = rtype;
        if (self.debug) {
            std.debug.print(message, args);
        }
        const formatted = try std.fmt.allocPrint(self.allocator, message, args);
        try self.errors.append(self.allocator, formatted);
    }
};
