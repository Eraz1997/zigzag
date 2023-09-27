const std = @import("std");

const settings = @import("./settings.zig");
const app = @import("./app.zig");

pub fn main() !void {
    const app_settings = settings.Settings{};
    var app_instance = app.App.init(app_settings);
    try app_instance.run();
}
