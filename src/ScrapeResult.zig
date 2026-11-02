/// Represents the JSON strings in a structed data format
const ScrapeResult = @This();

const std = @import("std");

url: []const u8,
fields: []const FieldResult,

pub const FieldResult = struct {
    key: []const u8,
    value: ?[]const u8,
};
