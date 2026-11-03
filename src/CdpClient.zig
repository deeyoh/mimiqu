/// Owns a web socket connection and sends CDP commands to
/// Lightpanda and is owned by a BrowserWorker
const CdpClient = @This();

const std = @import("std");
const ws = @import("websocket");

const Allocator = std.mem.Allocator;

allocator: Allocator,
client: ws.Client,
next_id: i64 = 1,
browser_context_id: ?[]const u8 = null,
target_id: ?[]const u8 = null,
session_id: ?[]const u8 = null,

pub fn connect(
    io: std.Io,
    allocator: Allocator,
    host: []const u8,
    port: u16,
) !CdpClient {
    var self: CdpClient = .{
        .allocator = allocator,
        .client = try ws.Client.init(io, allocator, .{
            .host = host,
            .port = port,
        }),
    };
    errdefer self.deinit();

    const headers = try Allocator.print(allocator, "Host: {s}:{d}\r\n", .{ host, port });
    defer allocator.free(headers);

    try self.client.handshake("/", .{
        .timeout_ms = 1000,
        .headers = headers,
    });

    var context = try self.sendBrowser("Target.createBrowserContext", .{
        .disposeOnDetach = true,
    });
    defer context.deinit();
    self.browser_context_id = try self.copyResultString(context.value, "browserContextId");

    var target = try self.sendBrowser("Target.createTarget", .{
        .url = "about:blank",
        .browserContextId = self.browser_context_id.?,
    });
    defer target.deinit();
    self.target_id = try self.copyResultString(target.value, "targetId");

    var attachment = try self.sendBrowser("Target.attachToTarget", .{
        .targetId = self.target_id.?,
        .flatten = true,
    });
    defer attachment.deinit();
    self.session_id = try self.copyResultString(attachment.value, "sessionId");

    return self;
}

pub fn deinit(self: *CdpClient) void {
    self.client.deinit();
    if (self.session_id) |id| self.allocator.free(id);
    if (self.target_id) |id| self.allocator.free(id);
    if (self.browser_context_id) |id| self.allocator.free(id);
    self.* = undefined;
}

fn copyResultString(self: *CdpClient, root: std.json.Value, key: []const u8) ![]const u8 {
    if (root != .object) return error.InvalidCdpResponse;
    const result = root.object.get("result") orelse return error.InvalidCdpResponse;
    if (result != .object) return error.InvalidCdpResponse;
    const value = result.object.get(key) orelse return error.InvalidCdpResponse;
    if (value != .string or value.string.len == 0) return error.InvalidCdpResponse;
    return self.allocator.dupe(u8, value.string);
}

pub fn send(
    self: *CdpClient,
    method: []const u8,
    params: anytype,
) !std.json.Parsed(std.json.Value) {
    const session_id = self.session_id orelse return error.CdpSessionNotInitialized;
    return self.sendCommand(session_id, method, params);
}

pub fn sendBrowser(
    self: *CdpClient,
    method: []const u8,
    params: anytype,
) !std.json.Parsed(std.json.Value) {
    return self.sendCommand(null, method, params);
}

fn sendCommand(
    self: *CdpClient,
    session_id: ?[]const u8,
    method: []const u8,
    params: anytype,
) !std.json.Parsed(std.json.Value) {
    const id = self.next_id;
    self.next_id += 1;

    const command = .{
        .id = id,
        .sessionId = session_id,
        .method = method,
        .params = params,
    };

    const serialized_command = try std.json.Stringify.valueAlloc(
        self.allocator,
        command,
        .{ .emit_null_optional_fields = false },
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
            },
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

        if (root.contains("error")) {
            std.log.err("CDP command failed: method={s}, id={d}, response={s}", .{
                method, id, msg.data,
            });
            parsed.deinit();
            return error.CdpCommandFailed;
        }

        return parsed;
    }
}
