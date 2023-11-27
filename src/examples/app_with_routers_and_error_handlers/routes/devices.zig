const std = @import("std");
const zigzag = @import("zigzag");

pub const Error = error{
    BadDevice,
};

pub fn create_router() zigzag.Router {
    var router = zigzag.Router.init("/devices");

    router.add_endpoint("/add", add);
    router.add_endpoint("/remove", remove);

    return router;
}

fn add(response: *std.http.Server.Response) !void {
    response.status = .created;
    try response.headers.append("content-type", "application/json");
    try response.do();
    try response.writeAll("{\"device_id\": \"dummy-id\"}");
    try response.finish();
}

fn remove(response: *std.http.Server.Response) !void {
    _ = response;
    return Error.BadDevice;
}
