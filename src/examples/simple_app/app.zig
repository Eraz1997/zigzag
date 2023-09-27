const std = @import("std");
const settings = @import("./settings.zig");

const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator(.{});
const Logger = std.log.scoped(.server);

pub const App = struct {
    address: []const u8 = "127.0.0.1",
    gpa: GeneralPurposeAllocator,
    allocator: std.mem.Allocator,
    port: u16,
    server: std.http.Server,
    should_quit: bool = false,

    pub fn init(app_settings: settings.Settings) App {
        Logger.info("Starting HTTP/1.1 server...", .{});

        var gpa = GeneralPurposeAllocator{};
        const allocator = gpa.allocator();

        var server = std.http.Server.init(allocator, .{ .reuse_address = true });

        return App{ .allocator = allocator, .gpa = gpa, .port = app_settings.port, .server = server };
    }

    pub fn run(self: *App) !void {
        defer std.debug.assert(self.gpa.deinit() == .ok);
        defer self.server.deinit();

        const address = std.net.Address.parseIp(self.address, self.port) catch unreachable;
        try self.server.listen(address);

        Logger.info("Server listening at {s}:{}", .{ self.address, self.port });

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

                handle_request(&response, self.allocator) catch |err| {
                    Logger.err("{}", .{err});
                };

                Logger.info("{s} {s} {s}", .{ @tagName(response.request.method), @tagName(response.request.version), response.request.target });
            }
        }
    }
};

fn handle_request(
    response: *std.http.Server.Response,
    allocator: std.mem.Allocator,
) !void {
    const body = try response.reader().readAllAlloc(allocator, 8192);
    defer allocator.free(body);

    if (response.request.headers.contains("connection")) {
        try response.headers.append("connection", "keep-alive");
    }

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
