const std = @import("std");
const Io = std.Io;

const mimiqu = @import("mimiqu");

const CdpClient = @import("CdpClient.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var cdp = CdpClient.init(io, init.gpa) catch |err| {
        std.log.err("Failed to connect to CDP: {s}", .{@errorName(err)});
        return err;
    };
    defer cdp.deinit();

    const response = try cdp.send("Browser.getVersion", struct {}{});
    defer response.deinit();
    std.debug.print("response: {any}\n", .{response.value});

    // const navi_response = try cdp.page_navigate("https://lightpanda.io/docs/reference/cli/serve");
    // defer navi_response.deinit();
    // std.debug.print("response: {any}\n", .{navi_response.value});

    // std.debug.print("cdp: {any}\n", .{cdp});
}
