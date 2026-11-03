const ScrapeJob = @This();

const std = @import("std");
const grpc = @import("grpc_lite");
const proto = @import("mimiqu_proto");

const ScrapeSpec = @import("ScrapeSpec.zig");

arena: std.heap.ArenaAllocator,
server_call: grpc.ServerCall,
spec: ?ScrapeSpec = null,

pub fn create(
    allocator: std.mem.Allocator,
    stream: grpc.ServerStream,
) !*ScrapeJob {
    const job = try allocator.create(ScrapeJob);
    errdefer allocator.destroy(job);

    var reply = try stream.retain();
    errdefer reply.deinit();

    job.* = .{
        .arena = std.heap.ArenaAllocator.init(allocator),
        .server_call = reply,
    };

    return job;
}

pub fn destroy(
    self: *ScrapeJob,
    allocator: std.mem.Allocator,
) void {
    self.server_call.deinit();
    self.arena.deinit();
    allocator.destroy(self);
}

/// `registerStream()` is lower level and causes `onMessage` callback to receive
/// serialized protobuf bytes ([]const u8) instead of decoded protobuf structs
pub fn decodeRequest(self: *ScrapeJob, payload: []const u8) !void {
    if (self.spec != null) return error.MultipleRequestMessages;

    const allocator = self.arena.allocator();
    var reader = std.Io.Reader.fixed(payload);
    const request = try proto.ScrapeRequest.decode(&reader, allocator);

    if (request.url.len == 0) return error.EmptyUrl;

    if (!std.mem.startsWith(u8, request.url, "http://") and
        !std.mem.startsWith(u8, request.url, "https://"))
    {
        return error.InvalidUrl;
    }

    const fields = try allocator.alloc(ScrapeSpec.ExtractionField, request.fields.items.len);

    for (request.fields.items, fields) |source, *destination| {
        if (source.name.len == 0 or source.selector.len == 0) return error.InvalidField;

        const extraction: ScrapeSpec.Extraction = switch (source.type) {
            .EXTRACTION_TYPE_TEXT => blk: {
                if (source.attribute.len != 0) return error.UnexpectedAttribute;
                break :blk .text;
            },
            .EXTRACTION_TYPE_HTML => blk: {
                if (source.attribute.len != 0) return error.UnexpectedAttribute;
                break :blk .html;
            },
            .EXTRACTION_TYPE_ATTRIBUTE => blk: {
                if (source.attribute.len == 0) return error.MissingAttribute;
                break :blk .{ .attribute = source.attribute };
            },
            else => return error.InvalidExtractionType,
        };

        destination.* = .{
            .name = source.name,
            .selector = source.selector,
            .extraction = extraction,
            .required = source.required,
        };
    }

    self.spec = .{
        .id = request.id,
        .url = request.url,
        .fields = fields,
        .timeout_ms = request.timeout_ms,
    };
}

pub fn fail(
    self: *ScrapeJob,
    code: grpc.StatusCode,
    message: []const u8,
) void {
    if (self.server_call.isTerminal()) return;

    self.server_call.finish(.{
        .code = code,
        .message = message,
    }, &.{}) catch {
        self.server_call.abort();
    };
}

fn decodeForTest(job: *ScrapeJob, request: proto.ScrapeRequest) !void {
    var writer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer writer.deinit();
    try request.encode(&writer.writer, std.testing.allocator);
    try job.decodeRequest(writer.written());
}

test "decoded request owns its strings after input is freed" {
    // Decoding does not use the call handle. Avoid destroying this fake handle.
    var job: ScrapeJob = .{
        .arena = std.heap.ArenaAllocator.init(std.testing.allocator),
        .server_call = undefined,
    };
    defer job.arena.deinit();

    var request: proto.ScrapeRequest = .{
        .id = 42,
        .url = "https://example.com",
        .timeout_ms = 500,
    };
    defer request.fields.deinit(std.testing.allocator);
    try request.fields.append(std.testing.allocator, .{
        .name = "link",
        .selector = "a",
        .type = .EXTRACTION_TYPE_ATTRIBUTE,
        .attribute = "href",
        .required = true,
    });

    // The serialized input buffer is freed before these assertions.
    try decodeForTest(&job, request);
    const spec = job.spec.?;
    try std.testing.expectEqual(@as(u32, 42), spec.id);
    try std.testing.expectEqualStrings(request.url, spec.url);
    try std.testing.expectEqual(@as(u32, 500), spec.timeout_ms);
    try std.testing.expectEqualStrings("link", spec.fields[0].name);
    try std.testing.expectEqualStrings("a", spec.fields[0].selector);
    try std.testing.expectEqualStrings("href", spec.fields[0].extraction.attribute);
    try std.testing.expect(spec.fields[0].required);
    try std.testing.expectError(error.MultipleRequestMessages, decodeForTest(&job, request));
}

test "reject invalid URLs and extraction combinations" {
    var job: ScrapeJob = .{
        .arena = std.heap.ArenaAllocator.init(std.testing.allocator),
        .server_call = undefined,
    };
    defer job.arena.deinit();

    try std.testing.expectError(error.EmptyUrl, decodeForTest(&job, .{}));
    try std.testing.expectError(error.InvalidUrl, decodeForTest(&job, .{ .url = "file:///etc/passwd" }));

    var request: proto.ScrapeRequest = .{ .url = "https://example.com" };
    defer request.fields.deinit(std.testing.allocator);
    try request.fields.append(std.testing.allocator, .{
        .name = "title",
        .selector = "h1",
        .type = .EXTRACTION_TYPE_TEXT,
        .attribute = "href",
    });
    try std.testing.expectError(error.UnexpectedAttribute, decodeForTest(&job, request));
    request.fields.items[0].type = .EXTRACTION_TYPE_ATTRIBUTE;
    request.fields.items[0].attribute = "";
    try std.testing.expectError(error.MissingAttribute, decodeForTest(&job, request));
    request.fields.items[0].type = .EXTRACTION_TYPE_UNSPECIFIED;
    try std.testing.expectError(error.InvalidExtractionType, decodeForTest(&job, request));
    request.fields.items[0].type = .EXTRACTION_TYPE_HTML;
    request.fields.items[0].name = "";
    try std.testing.expectError(error.InvalidField, decodeForTest(&job, request));
    try std.testing.expect(job.spec == null);
}

test "malformed protobuf is rejected" {
    var job: ScrapeJob = .{
        .arena = std.heap.ArenaAllocator.init(std.testing.allocator),
        .server_call = undefined,
    };
    defer job.arena.deinit();

    // URL field advertises five bytes, but has only one.
    if (job.decodeRequest(&.{ 0x12, 0x05, 'x' })) |_| {
        return error.ExpectedDecodeFailure;
    } else |_| {}
    try std.testing.expect(job.spec == null);
}
