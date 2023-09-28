const std = @import("std");
const zigzag = @import("zigzag");

pub fn main() !void {
    const settings = zigzag.Settings{ .address = "0.0.0.0", .port = 8000 };
    var app = zigzag.App.init(app_settings);
    try app.run();
}
