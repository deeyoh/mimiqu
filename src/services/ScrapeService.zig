const ScrapeService = @This();

const std = @import("std");
const grpc = @import("grpc_lite");

const BrowserPool = @import("../BrowserPool.zig");
const ScrapeJob = @import("../ScrapeJob.zig");

allocator: std.mem.Allocator,
pool: *BrowserPool,

// Reactor-owned request state. Submitted jobs are owned by the queue/worker.
// Destroy this map only after the server has stopped invoking callbacks.
pending: std.AutoHashMapUnmanaged(
    grpc.ServerCallId,
    *ScrapeJob,
) = .empty,

pub fn register(
    self: *ScrapeService,
    server: *grpc.Server,
) !void {
    try server.registerStream(
        "/mimiqu.v1.ScraperService/Scrape",
        .{
            .context = self,
            .on_start = onStart,
            .on_message = onMessage,
            .on_remote_end = onRemoteEnd,
            .on_terminal = onTerminal,
        },
    );
}

pub fn deinit(self: *ScrapeService) void {
    var values = self.pending.valueIterator();

    while (values.next()) |job| {
        job.*.destroy(self.allocator);
    }

    self.pending.deinit(self.allocator);
}

fn fromContext(context: ?*anyopaque) *ScrapeService {
    return @ptrCast(@alignCast(context.?));
}

fn onStart(
    context: ?*anyopaque,
    stream: grpc.ServerStream,
    _: *grpc.ServerContext,
) !void {
    const self = fromContext(context);

    const job = try ScrapeJob.create(self.allocator, stream);
    errdefer job.destroy(self.allocator);

    try self.pending.put(self.allocator, stream.id(), job);
}

fn onMessage(
    context: ?*anyopaque,
    stream: grpc.ServerStream,
    _: *grpc.ServerContext,
    payload: []const u8,
    _: grpc.Compression,
) !grpc.StreamReceiveAction {
    const self = fromContext(context);

    const job = self.pending.get(stream.id()) orelse return .continue_receiving;

    job.decodeRequest(payload) catch |err| {
        _ = self.pending.remove(stream.id());
        defer job.destroy(self.allocator);

        if (err == error.OutOfMemory) {
            job.fail(.resource_exhausted, "request allocation failed");
        } else {
            job.fail(.invalid_argument, "invalid scrape request");
        }
    };

    return .continue_receiving;
}

fn onRemoteEnd(
    context: ?*anyopaque,
    stream: grpc.ServerStream,
    rpc_context: *grpc.ServerContext,
) !void {
    const self = fromContext(context);

    const entry = self.pending.fetchRemove(stream.id()) orelse return;
    const job = entry.value;

    var submitted = false;
    defer if (!submitted) job.destroy(self.allocator);

    if (job.spec == null) {
        job.fail(.invalid_argument, "missing scrape request");
        return;
    }

    if (rpc_context.isDeadlineExceeded()) {
        job.fail(.deadline_exceeded, "deadline exceeded");
        return;
    }

    const accepted = self.pool.trySubmit(job) catch {
        job.fail(.unavailable, "scrape pool is unavailable");
        return;
    };

    if (!accepted) {
        job.fail(.resource_exhausted, "scrape queue is full");
        return;
    }

    // The worker may already be processing (or have destroyed) job.
    // Do not access it after ownership transfers to the queue.
    submitted = true;
}

fn onTerminal(
    context: ?*anyopaque,
    id: grpc.ServerCallId,
    _: grpc.ServerTerminalReason,
) void {
    const self = fromContext(context);

    if (self.pending.fetchRemove(id)) |entry| {
        entry.value.destroy(self.allocator);
    }
}
