const app = @import("./app.zig");
const std = @import("std");

pub const Task = struct {
    app: *app.App,
    response: *std.http.Server.Response,
    function: *const fn (*app.App, *std.http.Server.Response) void,
};
