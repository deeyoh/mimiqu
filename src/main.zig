const std = @import("std");
const Io = std.Io;

const mimiqu = @import("mimiqu");

const proto = @import("mimiqu_proto");
const grpc = @import("grpc_lite");
const grpc_pb = @import("grpc_lite_protobuf");

const CdpClient = @import("CdpClient.zig");

const VersionService = @import("services/VersionService.zig");
const EchoService = @import("services/EchoService.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;

    var server = try grpc.Server.init(allocator, .{ .host = "127.0.0.1", .port = 50051 });
    defer server.deinit();

    // == version service ==
    var version_service = VersionService{
        .allocator = allocator,
    };
    var version_registration: VersionService.Registration = undefined;
    try version_service.initAndRegister(
        allocator,
        &server,
        &version_registration,
    );
    defer version_registration.deinit();

    // == echo service ==
    var echo_service = EchoService{
        .allocator = allocator,
    };
    var echo_registration: EchoService.Registration = undefined;
    try echo_service.initAndRegister(
        allocator,
        &server,
        &echo_registration,
    );
    defer echo_registration.deinit();

    // ==
    // Server start
    // ==
    try server.start();

    std.debug.print("gRPC listening on 127.0.0.1:50051\n", .{});

    const io = init.io;
    var cdp = CdpClient.init(io, init.gpa) catch |err| {
        std.log.err("Failed to connect to CDP: {s}", .{@errorName(err)});
        return err;
    };
    defer cdp.deinit();

    const response = try cdp.send("Browser.getVersion", struct {}{});
    defer response.deinit();

    server.wait();
}

// pub fn main(init: std.process.Init) !void {
//     const io = init.io;
//     var cdp = CdpClient.init(io, init.gpa) catch |err| {
//         std.log.err("Failed to connect to CDP: {s}", .{@errorName(err)});
//         return err;
//     };
//     defer cdp.deinit();
//
//     const response = try cdp.send("Browser.getVersion", struct {}{});
//     defer response.deinit();
//     std.debug.print("response: {any}\n", .{response.value});
//
//     // const navi_response = try cdp.pageNavigate("https://lightpanda.io/docs/reference/cli/serve");
//     // defer navi_response.deinit();
//     // std.debug.print("response: {any}\n", .{navi_response.value});
//
//     // std.debug.print("cdp: {any}\n", .{cdp});
// }
