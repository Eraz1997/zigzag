const zigzag = @import("zigzag");
const users = @import("./routes/users.zig");
const devices = @import("./routes/devices.zig");
const error_handlers = @import("./error_handlers.zig");

pub fn main() void {
    // Init
    const settings = zigzag.Settings{ .address = "127.0.0.1", .port = 8080 };
    var app = zigzag.App.init(settings);

    // Add routers
    var router = users.create_router();
    const std = @import("std");
    std.log.debug("DONE {s}", .{router.prefix});
    app.add_router(router);
    app.add_router(devices.create_router());

    // Add error handler
    app.add_error_handler(users.Error.UserNotFoundError, error_handlers.handle_user_not_found_error);
    app.add_error_handler(devices.Error.BadDevice, error_handlers.handle_bad_device_error);

    // Run
    app.run();
}
