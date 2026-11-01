const VersionService = @This();

const std = @import("std");
const proto = @import("mimiqu_proto");
const build_options = @import("build_options");
const grpc = @import("grpc_lite");
const grpc_pb = @import("grpc_lite_protobuf");

const errors = @import("../errors.zig");

pub const Error = errors.AppError;
pub const Api = proto.VersionService(VersionService, Error);
pub const Registration = grpc_pb.ServiceRegistration(Api);

allocator: std.mem.Allocator,

pub fn initAndRegister(
    self: *VersionService,
    allocator: std.mem.Allocator,
    server: *grpc.Server,
    registration: *Registration,
) !void {
    registration.* = Registration.init(
        allocator,
        self,
        .{ .GetVersion = VersionService.getVersion },
        .{},
    );
    errdefer registration.deinit();

    try registration.register(server);
}

pub fn getVersion(
    self: *VersionService,
    request: proto.GetVersionRequest,
) Error!proto.GetVersionResponse {
    _ = request;

    return .{
        .version = try self.allocator.dupe(u8, build_options.app_version),
        .protocol_version = build_options.primary_protocol_version,
    };
}
