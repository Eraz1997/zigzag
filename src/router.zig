const std = @import("std");
const logging = @import("./logging.zig");
const memory = @import("./memory.zig");

const EndpointHandler = *const fn (*std.http.Server.Response) anyerror!void;

pub const RouterError = error{
    EndpointHandlerNotFound,
};

pub const Router = struct {
    allocator: std.mem.Allocator,
    gpa: memory.GeneralPurposeAllocator,
    prefix: []const u8 = "",
    endpoint_handlers: std.StringHashMap(EndpointHandler),

    pub fn init(prefix: []const u8) Router {
        var gpa = memory.GeneralPurposeAllocator{};
        const allocator = gpa.allocator();
        return Router{ .allocator = allocator, .prefix = prefix, .endpoint_handlers = std.StringHashMap(EndpointHandler).init(allocator) };
    }

    pub fn add_endpoint(self: *Router, path: []const u8, endpoint_handler: EndpointHandler) void {
        try self.endpoint_handlers.put(path, endpoint_handler) catch |err| {
            logging.Logger.err("Cannot register endpoint handler for path {}{}: {}", .{ self.prefix, path, err });
        };
    }

    pub fn get_endpoint_handler(self: *Router, path: []const u8) RouterError!EndpointHandler {
        if (path.len < self.prefix.len) {
            return RouterError.EndpointHandlerNotFound;
        }
        const path_without_prefix = path[self.prefix.len..];
        const path_prefix = path[0..self.prefix.len];
        if (!std.mem.eql(u8, path_prefix, self.prefix)) {
            return RouterError.EndpointHandlerNotFound;
        }
        return self.endpoint_handlers.get(path_without_prefix) orelse return RouterError.EndpointHandlerNotFound;
    }

    pub fn deinit(self: *Router) void {
        defer std.debug.assert(self.gpa.deinit() == .ok);
    }
};
