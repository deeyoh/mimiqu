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

    std.debug.print("cdp: {any}\n", .{cdp});
}
