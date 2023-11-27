const zigzag = @import("zigzag");

pub fn main() void {
    const settings = zigzag.Settings{ .address = "127.0.0.1", .port = 8080 };
    var app = zigzag.App.init(settings);
    app.run();
}
