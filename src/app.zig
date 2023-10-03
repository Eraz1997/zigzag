const std = @import("std");
const settings = @import("./settings.zig");
const logging = @import("./logging.zig");
const router = @import("./router.zig");

const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator(.{});

pub const App = struct {
    allocator: std.mem.Allocator,
    gpa: GeneralPurposeAllocator,
    server: std.http.Server,
    settings: settings.Settings,
    should_quit: bool = false,
    routers: std.ArrayList(*router.Router),

    pub fn init(app_settings: settings.Settings) App {
        logging.Logger.info("Starting HTTP/1.1 server...", .{});

        var gpa = GeneralPurposeAllocator{};
        const allocator = gpa.allocator();

        var server = std.http.Server.init(allocator, .{ .reuse_address = true });

        return App{ .allocator = allocator, .gpa = gpa, .server = server, .settings = app_settings, .routers = std.ArrayList(*router.Router).init(allocator) };
    }

    pub fn add_router(self: *App, app_router: *router.Router) void {
        try self.routers.append(app_router) catch |err| {
            logging.Logger.err("Cannot register router with prefix {}: {}", .{ app_router.prefix, err });
        };
    }

    pub fn run(self: *App) void {
        defer std.debug.assert(self.gpa.deinit() == .ok);
        defer self.server.deinit();
        defer for (self.routers.items) |app_router| {
            app_router.deinit();
        };
        defer self.routers.deinit();

        const address = std.net.Address.parseIp(self.settings.address, self.settings.port) catch unreachable;
        self.server.listen(address) catch |err| {
            logging.Logger.err("Cannot listen at {s}:{}: {}", .{ self.settings.address, self.settings.port, err });
            return;
        };

        logging.Logger.info("Server listening at {s}:{}", .{ self.settings.address, self.settings.port });

        while (true) {
            var response = self.server.accept(.{ .allocator = self.allocator }) catch |err| {
                logging.Logger.err("Cannot accept response: {}", .{err});
                continue;
            };
            defer response.deinit();

            while (response.reset() != .closing) {
                response.wait() catch |err| switch (err) {
                    error.HttpHeadersInvalid => break,
                    error.EndOfStream => continue,
                    else => {
                        logging.Logger.err("{}", .{err});
                        if (@errorReturnTrace()) |trace| {
                            std.debug.dumpStackTrace(trace.*);
                        }
                    },
                };

                const thread = std.Thread.spawn(.{ .allocator = self.allocator }, handle_request, .{
                    self,
                    &response,
                    self.allocator,
                    self.settings.max_body_size,
                }) catch |err| {
                    logging.Logger.err("Cannot spawn thread: {}", .{err});
                    break;
                };
                thread.join();
            }
        }
    }
};

fn handle_request(app: *App, response: *std.http.Server.Response, allocator: std.mem.Allocator, max_body_size: usize) void {
    const body = response.reader().readAllAlloc(allocator, max_body_size) catch |err| {
        logging.Logger.err("Cannot allocate space for body: {}", .{err});
        response.status = .internal_server_error;
        log_response_info(response);
        return;
    };
    defer allocator.free(body);

    if (response.request.headers.contains("connection")) {
        response.headers.append("connection", "keep-alive") catch |err| {
            logging.Logger.err("Cannot set 'connection' header: {}", .{err});
        };
    }

    for (app.routers.items) |app_router| {
        const endpoint_handler = app_router.get_endpoint_handler(response.request.target) catch |err| {
            switch (err) {
                router.RouterError.EndpointHandlerNotFound => continue,
            }
        };
        endpoint_handler(response) catch |err| {
            response.status = .internal_server_error;
            logging.Logger.err("{}", .{err});
            response.do() catch |err1| {
                logging.Logger.err("Could not start response: {}", .{err1});
            };
            response.finish() catch |err1| {
                logging.Logger.err("Could not flush response: {}", .{err1});
            };
        };
        log_response_info(response);
        return;
    }

    response.status = .not_found;
    response.do() catch |err| {
        logging.Logger.err("Could not start response: {}", .{err});
    };
    response.finish() catch |err| {
        logging.Logger.err("Could not flush response: {}", .{err});
    };
}

fn log_response_info(response: *std.http.Server.Response) void {
    logging.Logger.info("{s} {s} {s} - {}", .{ @tagName(response.request.method), @tagName(response.request.version), response.request.target, @intFromEnum(response.status) });
}
