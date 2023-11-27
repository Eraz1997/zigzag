const std = @import("std");

pub const ErrorHandler = *const fn (*std.http.Server.Response) anyerror!void;

pub fn handle_user_not_found_error(response: *std.http.Server.Response) !void {
    response.status = .not_found;
    try response.headers.append("content-type", "application/json");
    try response.do();
    try response.writeAll("{\"error_code\": \"users.not_found\"}");
    try response.finish();
}

pub fn handle_bad_device_error(response: *std.http.Server.Response) !void {
    response.status = .internal_server_error;
    try response.headers.append("content-type", "application/json");
    try response.do();
    try response.writeAll("{\"error_code\": \"devices.bad_device\", \"device_id\": 1234}");
    try response.finish();
}
