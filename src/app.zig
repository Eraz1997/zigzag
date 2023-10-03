const std = @import("std");
const settings = @import("./settings.zig");
const logging = @import("./logging.zig");
const router = @import("./router.zig");
const errors = @import("./errors.zig");
const error_handlers = @import("./error_handlers.zig");

const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator(.{});

pub const App = struct {
    allocator: std.mem.Allocator,
    gpa: GeneralPurposeAllocator,
    server: std.http.Server,
    settings: settings.Settings,
    should_quit: bool = false,
    routers: std.ArrayList(*router.Router),
    error_handlers: std.AutoHashMap(anyerror, error_handlers.ErrorHandler),

    pub fn init(app_settings: settings.Settings) App {
        logging.Logger.info("Starting HTTP/1.1 server...", .{});

        var gpa = GeneralPurposeAllocator{};
        const allocator = gpa.allocator();

        var server = std.http.Server.init(allocator, .{ .reuse_address = true });

        var default_error_handlers = std.AutoHashMap(anyerror, error_handlers.ErrorHandler).init(allocator);
        default_error_handlers.put(errors.ZigZagError.NotFound, error_handlers.handle_not_found) catch |err| {
            logging.Logger.err("Cannot register default error handler: {}", .{err});
        };
        default_error_handlers.put(errors.ZigZagError.InternalError, error_handlers.handle_internal_error) catch |err| {
            logging.Logger.err("Cannot register default error handler: {}", .{err});
        };

        return App{
            .allocator = allocator,
            .gpa = gpa,
            .server = server,
            .settings = app_settings,
            .routers = std.ArrayList(*router.Router).init(allocator),
            .error_handlers = default_error_handlers,
        };
    }

    pub fn add_router(self: *App, app_router: *router.Router) void {
        try self.routers.append(app_router) catch |err| {
            logging.Logger.err("Cannot register router with prefix {}: {}", .{ app_router.prefix, err });
        };
    }

    pub fn add_error_handler(self: *App, err: anyerror, handler: error_handlers.ErrorHandler) void {
        try self.error_handlers.put(err, handler) catch |insertion_error| {
            logging.Logger.err("Could not register error handler for {}: {}", .{ err, insertion_error });
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

    execute_endpoint_handler(app, response) catch |err| {
        const error_handler = app.error_handlers.get(err) orelse app.error_handlers.get(errors.ZigZagError.InternalError) orelse return {
            logging.Logger.err("Cannot error handler for {}", .{err});
        };
        error_handler(response) catch |unexpected_error| {
            logging.Logger.err("Unexpected error while handling managed error: {}", .{unexpected_error});
        };
    };
}

fn execute_endpoint_handler(app: *App, response: *std.http.Server.Response) !void {
    for (app.routers.items) |app_router| {
        const endpoint_handler = app_router.get_endpoint_handler(response.request.target) catch |err| {
            switch (err) {
                router.RouterError.EndpointHandlerNotFound => continue,
            }
        };
        try endpoint_handler(response);
        log_response_info(response);
        return;
    }

    return errors.ZigZagError.NotFound;
}

fn log_response_info(response: *std.http.Server.Response) void {
    logging.Logger.info("{s} {s} {s} - {}", .{ @tagName(response.request.method), @tagName(response.request.version), response.request.target, @intFromEnum(response.status) });
}
