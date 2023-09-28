const std = @import("std");
const settings = @import("./settings.zig");

const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator(.{});
const Logger = std.log.scoped(.server);

pub const App = struct {
    allocator: std.mem.Allocator,
    gpa: GeneralPurposeAllocator,
    server: std.http.Server,
    settings: settings.Settings,
    should_quit: bool = false,

    pub fn init(app_settings: settings.Settings) App {
        Logger.info("Starting HTTP/1.1 server...", .{});

        var gpa = GeneralPurposeAllocator{};
        const allocator = gpa.allocator();

        var server = std.http.Server.init(allocator, .{ .reuse_address = true });

        return App{ .allocator = allocator, .gpa = gpa, .server = server, .settings = app_settings };
    }

    pub fn run(self: *App) !void {
        defer std.debug.assert(self.gpa.deinit() == .ok);
        defer self.server.deinit();

        const address = std.net.Address.parseIp(self.settings.address, self.settings.port) catch unreachable;
        try self.server.listen(address);

        Logger.info("Server listening at {s}:{}", .{ self.settings.address, self.settings.port });

        while (true) {
            var response = try self.server.accept(.{ .allocator = self.allocator });
            defer response.deinit();

            while (response.reset() != .closing) {
                response.wait() catch |err| switch (err) {
                    error.HttpHeadersInvalid => break,
                    error.EndOfStream => continue,
                    else => {
                        Logger.err("{}", .{err});
                        if (@errorReturnTrace()) |trace| {
                            std.debug.dumpStackTrace(trace.*);
                        }
                    },
                };

                const thread = try std.Thread.spawn(.{ .allocator = self.allocator }, handle_request, .{
                    &response,
                    self.allocator,
                    self.settings.max_body_size,
                });
                thread.join();
            }
        }
    }
};

fn handle_request(response: *std.http.Server.Response, allocator: std.mem.Allocator, max_body_size: usize) void {
    const body = response.reader().readAllAlloc(allocator, max_body_size) catch |err| {
        Logger.err("Cannot allocate space for body: {}", .{err});
        response.status = .internal_server_error;
        log_response_info(response);
        return;
    };
    defer allocator.free(body);

    if (response.request.headers.contains("connection")) {
        response.headers.append("connection", "keep-alive") catch |err| {
            Logger.err("Cannot set 'connection' header: {}", .{err});
        };
    }

    example_router(response) catch |err| {
        Logger.err("{}", .{err});
    };

    log_response_info(response);
}

fn log_response_info(response: *std.http.Server.Response) void {
    Logger.info("{s} {s} {s} - {}", .{ @tagName(response.request.method), @tagName(response.request.version), response.request.target, @intFromEnum(response.status) });
}

fn example_router(response: *std.http.Server.Response) !void {
    if (std.mem.startsWith(u8, response.request.target, "/test") and response.request.method == .GET) {
        try response.headers.append("content-type", "text/plain");
        response.status = .ok;
        response.transfer_encoding = .{ .content_length = 14 };
        try response.do();
        try response.writeAll("Hello, ");
        try response.writeAll("World!\n");
        try response.finish();
    } else {
        try response.headers.append("content-type", "text/plain");
        response.status = .not_found;
        try response.do();
    }
}
