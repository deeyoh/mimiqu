const std = @import("std");
const Io = std.Io;

const mimiqu = @import("mimiqu");

const proto = @import("mimiqu_proto");
const grpc = @import("grpc_lite");
const grpc_pb = @import("grpc_lite_protobuf");

const CdpClient = @import("CdpClient.zig");

const AppError = error{OutOfMemory};
const State = struct {
    allocator: std.mem.Allocator,

    fn echo(self: *State, request: proto.EchoRequest) AppError!proto.EchoResponse {
        return .{ .message = try self.allocator.dupe(u8, request.message) };
    }
};
const EchoApi = proto.EchoService(State, AppError);

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var state = State{ .allocator = allocator };

    var registration = grpc_pb.ServiceRegistration(EchoApi).init(
        allocator,
        &state,
        .{ .Echo = State.echo },
        .{},
    );
    defer registration.deinit();

    var server = try grpc.Server.init(allocator, .{
        .host = "127.0.0.1",
        .port = 50051
    });
    defer server.deinit();

    try registration.register(&server);
    try server.start();

    std.debug.print("gRPC listening on 127.0.0.1:50051\n", .{});

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
//     // const navi_response = try cdp.page_navigate("https://lightpanda.io/docs/reference/cli/serve");
//     // defer navi_response.deinit();
//     // std.debug.print("response: {any}\n", .{navi_response.value});
//
//     // std.debug.print("cdp: {any}\n", .{cdp});
// }
