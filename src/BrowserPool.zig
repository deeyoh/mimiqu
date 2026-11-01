const BrowserPool = @This();

const std = @import("std");
const CdpClient = @import("CdpClient.zig");

const BrowserCtxSlot = struct {
    context_id: []const u8,
    target_id: []const u8,
    session_id: []const u8,
    busy: bool = false,
};

allocator: std.mem.Allocator,
cdp: *CdpClient,
context_slots: []BrowserCtxSlot,

pub fn init(
    allocator: std.mem.Allocator,
    cdp: *CdpClient,
    size: usize,
) !BrowserPool {
    if (size == 0) return error.InvalidPoolSize;

    const context_slots = try allocator.alloc(BrowserCtxSlot, size);
    errdefer allocator.free(context_slots);

    var initialized_count: usize = 0;
    errdefer {
        for (context_slots[0..initialized_count]) |slot| {
            destroySlot(allocator, cdp, slot);
        }
    }

    for (context_slots) |*slot| {
        slot.* = try createSlot(allocator, cdp);
        initialized_count += 1;
    }

    return .{
        .allocator = allocator,
        .cdp = cdp,
        .context_slots = context_slots,
    };
}

pub fn deinit(self: *BrowserPool) void {
    for (self.context_slots) |slot| {
        destroySlot(self.allocator, self.cdp, slot);
    }
    self.allocator.free(self.context_slots);
}

fn destroySlot(
    allocator: std.mem.Allocator,
    cdp: *CdpClient,
    slot: BrowserCtxSlot,
) void {
    diposeContext(cdp, slot.context_id);

    allocator.free(slot.context_id);
    allocator.free(slot.target_id);
    allocator.free(slot.session_id);
}

fn createSlot(
    allocator: std.mem.Allocator,
    cdp: *CdpClient,
) !BrowserCtxSlot {
    const browser_ctx_res = try cdp.send("Target.createBrowserContext", struct{}{});
    defer browser_ctx_res.deinit();

    const ctx_result = try getResult(browser_ctx_res.value);
    const ctx_id_val = try getField(ctx_result, "browserContextId");

    if (ctx_id_val != .string) {
        return error.InvalidResponse;
    }
    const ctx_id = ctx_id_val.string;
    // at this point Chrome has already created the browser context. If anything after this extraction fails,
    // the browser context stays alive in Chrome with nothing tracking it -> cleanup.
    errdefer diposeContext(cdp, ctx_id);

    const create_target_res = try cdp.send("Target.createTarget", .{
        .url = "about:blank",
        .browserContextId = ctx_id,
    });
    defer create_target_res.deinit();

    const create_target_result = try getResult(create_target_res.value);
    const target_id_val = try getField(create_target_result, "targetId");

    if (target_id_val != .string) {
        return error.InvalidResponse;
    }
    const target_id = target_id_val.string;


    //attach to target for session
    const attach_res = try cdp.send("Target.attachToTarget", .{
        .targetId = target_id,
        .flatten = true
    });
    defer attach_res.deinit();

    const attach_result = try getResult(attach_res.value);
    const session_id_val = try getField(attach_result, "sessionId");

    if (session_id_val != .string) {
        return error.InvalidResponse;
    }
    const session_id = session_id_val.string;


    const owned_ctx_id = try allocator.dupe(u8, ctx_id);
    errdefer allocator.free(owned_ctx_id);

    const owned_target_id = try allocator.dupe(u8, target_id);
    errdefer allocator.free(owned_target_id);

    const owned_session_id = try allocator.dupe(u8, session_id);
    errdefer allocator.free(owned_session_id);

    return .{
        .context_id = owned_ctx_id,
        .target_id = owned_target_id,
        .session_id = owned_session_id,
    };
}

//a best effort cleanup. If connection is broken, remote cleanup may not be possible
fn diposeContext(cdp: *CdpClient, context_id: []const u8) void {
    const response = cdp.send("Target.disposeBrowserContext", .{
        .browserContextId = context_id,
    }) catch |err| {
        std.log.err(
            "Failed to dispose browser context {s}: {s}",
            .{ context_id, @errorName(err) },
        );
        return;
    };
    defer response.deinit();

    _ = getResult(response.value) catch |err| {
        std.log.err(
            "Invalid or failed dispose response for context {s}: {s}",
            .{ context_id, @errorName(err) },
        );
        return;
    };
}

/// CDP protocol returns answers in the following structure:
///
/// ```
/// {
///     "id": 2,
///     "result": {
///         ...
///     }
/// }
/// ```
fn getResult(response: std.json.Value) !std.json.Value {
    if (response != .object) {
        return error.InvalidResponse;
    }

    if (response.object.get("error")) |cdp_error| {
        std.log.err("CDP command failed: {any}", .{cdp_error});
        return error.CdpCommandFailed;
    }

    const result = try getField(response, "result");
    if (result != .object) return error.InvalidResponse;
    return result;
}

fn getField(
    value: std.json.Value,
    key: []const u8,
) !std.json.Value {
    if (value != .object) {
        return error.InvalidResponse;
    }

    return value.object.get(key)
        orelse error.InvalidResponse;
}
