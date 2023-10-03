const std = @import("std");

pub const ErrorHandler = *const fn (*std.http.Server.Response) anyerror!void;

pub fn handle_not_found(response: *std.http.Server.Response) !void {
    response.status = .not_found;
    try response.do();
    try response.finish();
}

pub fn handle_internal_error(response: *std.http.Server.Response) !void {
    response.status = .internal_server_error;
    try response.do();
    try response.finish();
}
