const VersionService = @This();

const std = @import("std");
const proto = @import("mimiqu_proto");
const build_options = @import("build_options");

const errors = @import("../errors.zig");

pub const Error = errors.AppError;
pub const Api = proto.VersionService(VersionService, Error);

allocator: std.mem.Allocator,

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
