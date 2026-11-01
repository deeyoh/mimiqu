const std = @import("std");
const ws = @import("websocket");

const Allocator = std.mem.Allocator;

const CdpClient = @This();

allocator: Allocator,
client: ws.Client,
next_id: i64 = 1,

pub fn init(io: std.Io, allocator: Allocator) !CdpClient {
    var client = try ws.Client.init(io, allocator, .{ .host = "127.0.0.1", .port = 9222 });
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

// pub fn pageNavigate(self: *CdpClient, url: []const u8) !std.json.Parsed(std.json.Value) {
//     const response = try self.send("Page.navigate", .{
//         .url = url,
//     });
//     errdefer response.deinit();
//
//     if (response.value.object.get("error") != null) {
//         return error.CdpCommandFailed;
//     }
//
//     const result = response.value.object.get("result") orelse {
//         return error.InvalidResponse;
//     };
//
//     if (result != .object) {
//         return error.InvalidResponse;
//     }
//
//     if (result.object.get("errorText")) |error_text| {
//         std.debug.print("Navigation failed: {any}\n", .{error_text});
//         return error.NavigationFailed;
//     }
//
//     return response;
// }

pub fn sendToSession(
    self: *CdpClient,
    session_id: []const u8,
    method: []const u8,
    params: anytype,
) !std.json.Parsed(std.json.Value) {
    return self.send(session_id, method, params);
}

pub fn send(
    self: *CdpClient,
    session_id: ?[]const u8,
    method: []const u8,
    params: anytype,
) !std.json.Parsed(std.json.Value) {
    const id = self.next_id;
    self.next_id += 1;

    const command = .{
        .id = id,
        .method = method,
        .params = params,
        .sessionId = session_id,
    };

    const payload = try std.json.Stringify.valueAlloc(self.allocator, command, .{ .emit_null_optional_fields = false });
    defer self.allocator.free(payload);

    std.debug.print("sending: {s}\n", .{payload});
    try self.client.write(payload);

    while (true) {
        const msg = (try self.client.read()) orelse continue;
        defer self.client.done(msg);

        switch (msg.type) {
            .close => return error.ConnectionClosed,
            .text => {
                std.debug.print("received: {s}\n", .{msg.data});
            },
            else => continue,
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

        const response_id = parsed.value.object.get("id") orelse {
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
            continue;
        }

        return parsed;
    }
}
