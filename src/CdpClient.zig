const std = @import("std");
const ws = @import("websocket");

const Allocator = std.mem.Allocator;

const CdpClient = @This();

allocator: Allocator,
client: ws.Client,

pub fn init(io: std.Io, allocator: Allocator) !CdpClient {
    var client = try ws.Client.init(io, allocator, .{
        .host = "127.0.0.1",
        .port = 9222
    });
    errdefer client.deinit();

    try client.handshake("/", .{
        .timeout_ms = 1000,
        .headers = "Host: 127.0.0.1:9222\r\n",
    });
    return .{
        .allocator = allocator,
        .client = client,
    };
}

pub fn deinit(self: *CdpClient) void {
    self.client.deinit();
}
