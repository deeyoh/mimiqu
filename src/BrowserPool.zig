const BrowserPool = @This();

const std = @import("std");
const ScrapeJob = @import("ScrapeJob.zig");
const BrowserWorker = @import("BrowserWorker.zig");
const CdpClient = @import("CdpClient.zig");

const Allocator = std.mem.Allocator;

allocator: std.mem.Allocator,
io: std.Io,

workers: []BrowserWorker,
jobs: std.Io.Queue(*ScrapeJob),
job_storage: []*ScrapeJob,

group: std.Io.Group = .init,

pub fn init(
    allocator: Allocator,
    io: std.Io,
    endpoint: []const u8,
    pool_size: usize,
) !BrowserPool {
    if (pool_size == 0) return error.InvalidPoolSize;

    const workers = try allocator.alloc(BrowserWorker, pool_size);
    errdefer allocator.free(workers);

    const job_storage = try allocator.alloc(*ScrapeJob, pool_size * 4);
    errdefer allocator.free(job_storage);

    //@TODO: Switch to more robust system, right now just expects a simple host:port
    const separator = std.mem.findScalarLast(u8, endpoint, ':') orelse return error.MissingPort;

    const host = endpoint[0..separator];
    if (host.len == 0) return error.MissingHost;

    const port = try std.fmt.parseInt(
        u16,
        endpoint[separator + 1 ..],
        10,
    );

    var initialized: usize = 0;

    errdefer {
        for (workers[0..initialized]) |*worker| {
            worker.cdp.deinit();
        }
    }

    for (workers, 0..) |*worker, index| {
        worker.* = .{ .id = index, .cdp = try CdpClient.connect(
            io,
            allocator,
            host,
            port,
        ) };
        initialized += 1;
    }

    return .{
        .allocator = allocator,
        .io = io,
        .workers = workers,
        .jobs = .init(job_storage),
        .job_storage = job_storage,
    };
}

pub fn start(self: *BrowserPool) !void {
    // Join any workers already started before propagating a startup failure.
    errdefer {
        self.jobs.close(self.io);
        self.group.await(self.io) catch {};
    }

    for (self.workers) |*worker| {
        try self.group.concurrent(self.io, BrowserWorker.run, .{
            worker,
            self.io,
            self.allocator,
            &self.jobs,
        });
    }
}

/// Success transfers ownership of the job to the queue.
/// On false (queue full) or error, ownership remains with the caller.
pub fn trySubmit(self: *BrowserPool, job: *ScrapeJob) !bool {
    const items = [_]*ScrapeJob{job};

    const count = try self.jobs.put(self.io, &items, 0);

    return count == 1;
}

pub fn shutdown(self: *BrowserPool) !void {
    self.jobs.close(self.io);

    try self.group.await(self.io);

    for (self.workers) |*worker| {
        worker.cdp.deinit();
    }

    self.allocator.free(self.workers);
    self.allocator.free(self.job_storage);
}

test "queue admission rejects full and closed queues without transferring ownership" {
    const io = std.testing.io;
    var storage: [1]*ScrapeJob = undefined;
    var pool: BrowserPool = .{
        .allocator = std.testing.allocator,
        .io = io,
        .workers = &.{},
        .jobs = .init(&storage),
        .job_storage = &storage,
    };
    // Admission stores pointers only; these jobs are never executed.
    var first: ScrapeJob = undefined;
    var second: ScrapeJob = undefined;

    try std.testing.expect(try pool.trySubmit(&first));
    try std.testing.expect(!try pool.trySubmit(&second));
    try std.testing.expectEqual(&first, try pool.jobs.getOne(io));
    try std.testing.expect(try pool.trySubmit(&second));
    pool.jobs.close(io);
    try std.testing.expectError(error.Closed, pool.trySubmit(&first));
    try std.testing.expectEqual(&second, try pool.jobs.getOne(io));
    try std.testing.expectError(error.Closed, pool.jobs.getOne(io));
}
