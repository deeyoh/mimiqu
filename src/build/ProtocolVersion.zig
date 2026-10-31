const ProtocolVersion = @This();

const std = @import("std");
const manifest = @import("../../build.zig.zon");

pub const supported = [_]u32{1};
pub const primary: u32 = supported[supported.len - 1];
pub const app_version: []const u8 = manifest.version;

options: *std.Build.Step.Options,

pub fn init(b: *std.Build) ProtocolVersion {
    const options = b.addOptions();

    options.addOption([]const u8, "app_version", app_version);
    options.addOption(u32, "primary_protocol_version", primary);
    options.addOption(
        []const u32,
        "supported_protocol_versions",
        &supported,
    );

    return .{
        .options = options,
    };
}
