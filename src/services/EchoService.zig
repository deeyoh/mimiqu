const EchoService = @This();

const std = @import("std");
const proto = @import("mimiqu_proto");
const grpc = @import("grpc_lite");
const grpc_pb = @import("grpc_lite_protobuf");

const errors = @import("../errors.zig");

pub const Error = errors.AppError;
pub const Api = proto.EchoService(EchoService, Error);
pub const Registration = grpc_pb.ServiceRegistration(Api);

allocator: std.mem.Allocator,

pub fn initAndRegister(
    self: *EchoService,
    allocator: std.mem.Allocator,
    server: *grpc.Server,
    registration: *Registration,
) !void {
    registration.* = Registration.init(
        allocator,
        self,
        .{ .Echo = EchoService.echo },
        .{},
    );
    errdefer registration.deinit();

    try registration.register(server);
}

pub fn echo(
    self: *EchoService,
    request: proto.EchoRequest,
) Error!proto.EchoResponse {
    std.debug.print("Received echo request: {s}\n", .{request.message});
    return .{ .message = try self.allocator.dupe(u8, request.message) };
}
