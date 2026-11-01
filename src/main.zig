const std = @import("std");
const Io = std.Io;

const mimiqu = @import("mimiqu");

const proto = @import("mimiqu_proto");
const grpc = @import("grpc_lite");
const grpc_pb = @import("grpc_lite_protobuf");

const CdpClient = @import("CdpClient.zig");
const BrowserPool = @import("BrowserPool.zig");

const VersionService = @import("services/VersionService.zig");
const EchoService = @import("services/EchoService.zig");
const ScrapeService = @import("services/ScrapeService.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var server = try grpc.Server.init(allocator, .{ .host = "127.0.0.1", .port = 50051 });
    defer server.deinit();

    var pool = try BrowserPool.init(
        allocator,
        init.io,
        "127.0.0.1:9222",
        1
    );
    try pool.start();
    defer pool.shutdown() catch {};

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

    // == scrape service ==
    var scrape_service = ScrapeService{
        .allocator = allocator,
        .pool = &pool,
    };
    var scrape_registgration: ScrapeService.Registration = undefined;
    try scrape_service.initAndRegister(allocator, &server, &scrape_registgration);
    defer scrape_registgration.deinit();

    // ==
    // Server start
    // ==
    try server.start();

    std.debug.print("gRPC listening on 127.0.0.1:50051\n", .{});

    server.wait();
}
