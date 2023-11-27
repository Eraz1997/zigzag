const std = @import("std");
const zigzag = @import("zigzag");

pub const Error = error{
    UserNotFoundError,
};

pub fn create_router() zigzag.Router {
    var router = zigzag.Router.init("/users");
    router.add_endpoint("/login", login);
    router.add_endpoint("/register", register);

    return router;
}

fn login(response: *std.http.Server.Response) !void {
    _ = response;
    return Error.UserNotFoundError;
}

fn register(response: *std.http.Server.Response) !void {
    response.status = .created;
    try response.headers.append("content-type", "application/json");
    try response.do();
    try response.writeAll("{\"user_id\": \"dummy-id\"}");
    try response.finish();
}
