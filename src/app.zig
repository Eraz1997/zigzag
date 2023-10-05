const std = @import("std");
const settings = @import("./settings.zig");
const logging = @import("./logging.zig");
const router = @import("./router.zig");
const errors = @import("./errors.zig");
const error_handlers = @import("./error_handlers.zig");
const memory = @import("./memory.zig");
const thread_pool = @import("./thread_pool.zig");

pub const App = struct {
    allocator: std.mem.Allocator,
    gpa: memory.GeneralPurposeAllocator,
    server: std.http.Server,
    settings: settings.Settings,
    routers: std.ArrayList(*router.Router),
    error_handlers: std.AutoHashMap(anyerror, error_handlers.ErrorHandler),
    thread_pool: thread_pool.ThreadPool,

    pub fn init(app_settings: settings.Settings) App {
        var gpa = memory.GeneralPurposeAllocator{};
        const allocator = gpa.allocator();

        var server = std.http.Server.init(allocator, .{ .reuse_address = true });

        var default_error_handlers = std.AutoHashMap(anyerror, error_handlers.ErrorHandler).init(allocator);
        default_error_handlers.put(errors.Error.NotFound, error_handlers.handle_not_found) catch |err| {
            logging.Logger.err("Cannot register default error handler: {}", .{err});
        };
        default_error_handlers.put(errors.Error.InternalError, error_handlers.handle_internal_error) catch |err| {
            logging.Logger.err("Cannot register default error handler: {}", .{err});
        };

        var app = App{
            .allocator = allocator,
            .gpa = gpa,
            .server = server,
            .settings = app_settings,
            .routers = std.ArrayList(*router.Router).init(allocator),
            .error_handlers = default_error_handlers,
            .thread_pool = thread_pool.ThreadPool.init(),
        };

        logging.Logger.info("App initialised.", .{});

        return app;
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
        logging.Logger.info("Starting HTTP/1.1 server...", .{});
        defer self.quit();

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

    fn quit(self: *App) void {
        logging.Logger.info("Gracefully quitting the application...", .{});

        std.debug.assert(self.gpa.deinit() == .ok);
        self.server.deinit();
        for (self.routers.items) |app_router| {
            app_router.deinit();
        }
        self.routers.deinit();
        self.thread_pool.deinit();

        logging.Logger.info("App gracefully shut down.", .{});

        std.os.exit(0);
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
        const error_handler = app.error_handlers.get(err) orelse app.error_handlers.get(errors.Error.InternalError) orelse return {
            logging.Logger.err("Cannot error handler for {}", .{err});
        };
        error_handler(response) catch |unexpected_error| {
            logging.Logger.err("Unexpected error while handling managed error: {}", .{unexpected_error});
        };
    };
    log_response_info(response);
}

fn execute_endpoint_handler(app: *App, response: *std.http.Server.Response) !void {
    for (app.routers.items) |app_router| {
        const endpoint_handler = app_router.get_endpoint_handler(response.request.target) catch |err| {
            switch (err) {
                router.RouterError.EndpointHandlerNotFound => continue,
            }
        };
        try endpoint_handler(response);
        return;
    }

    return errors.Error.NotFound;
}

fn log_response_info(response: *std.http.Server.Response) void {
    logging.Logger.info("{s} {s} {s} - {}", .{ @tagName(response.request.method), @tagName(response.request.version), response.request.target, @intFromEnum(response.status) });
}
