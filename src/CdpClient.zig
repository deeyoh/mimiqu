/// Owns a web socket connection and sends CDP commands to
/// Lightpanda and is owned by a BrowserWorker
const CdpClient = @This();

const std = @import("std");
const ws = @import("websocket");

const Allocator = std.mem.Allocator;

allocator: Allocator,
client: ws.Client,
next_id: i64 = 1,

pub fn connect(
    io: std.Io,
    allocator: Allocator,
    host: []const u8,
    port: u16,
) !CdpClient {
    var client = try ws.Client.init(io, allocator, .{
        .host = host,
        .port = port,
    });
    errdefer client.deinit();

    const headers = try Allocator.print(allocator, "Host: {s}:{d}\r\n", .{ host, port });
    defer allocator.free(headers);

    try client.handshake("/", .{
        .timeout_ms = 1000,
        .headers = headers,
    });

    return .{ .allocator = allocator, .client = client };
}

pub fn deinit(self: *CdpClient) void {
    self.client.deinit();
}

pub fn send(
    self: *CdpClient,
    method: []const u8,
    params: anytype,
) !std.json.Parsed(std.json.Value) {
    const id = self.next_id;
    self.next_id += 1;

    const command = .{
        .id = id,
        .method = method,
        .params = params,
    };

    const serialized_command = try std.json.Stringify.valueAlloc(
        self.allocator,
        command,
        .{},
    );
    defer self.allocator.free(serialized_command);

    try self.client.write(serialized_command);

    while (true) {
        //a websocket message
        const msg = (try self.client.read()) orelse continue;
        defer self.client.done(msg);

        switch (msg.type) {
            .close => return error.ConnectionClosed,
            .text => {
                std.log.info("received: {s}\n", .{msg.data});
            },
            else => {
                std.log.warn("skipping unaccounted message: {s}\n", .{msg.data});
                continue;
            }
        }

        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            msg.data,
            .{ .allocate = .alloc_always },
        );

        if (parsed.value != .object) {
            parsed.deinit();
            continue;
        }

        const root = parsed.value.object;

        const response_id = root.get("id") orelse {
            parsed.deinit();
            continue;
        };

        if (response_id != .integer) {
            parsed.deinit();
            continue;
        }

        const received_id = std.math.cast(
            @TypeOf(id),
            response_id.integer,
        ) orelse {
            parsed.deinit();
            continue;
        };

        if (received_id != id) {
            parsed.deinit();
            return error.UnexpectedResponseId;
        }

        return parsed;
    }
}



// client: ws.Client,
// next_id: i64 = 1,
//
//
// pub fn sendToSession(
//     self: *CdpClient,
//     session_id: []const u8,
//     method: []const u8,
//     params: anytype,
// ) !std.json.Parsed(std.json.Value) {
//     return self.send(session_id, method, params);
// }
