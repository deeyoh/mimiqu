const BrowserPool = @This();

const std = @import("std");
const ScrapeSpec = @import("ScrapeSpec.zig");
const ScrapeResult = @import("ScrapeResult.zig");
const BrowserWorker = @import("BrowserWorker.zig");
const CdpClient = @import("CdpClient.zig");

const Allocator = std.mem.Allocator;

allocator: std.mem.Allocator,
io: std.Io,

workers: []BrowserWorker,

jobs: std.Io.Queue(ScrapeSpec),
results: std.Io.Queue(ScrapeResult),

job_storage: []ScrapeSpec,
result_storage: []ScrapeResult,

group: std.Io.Group = .init,

pub fn init(
    allocator: Allocator,
    io: std.Io,
    endpoint: []const u8,
    pool_size: usize,
) !BrowserPool {
    const workers = try allocator.alloc(BrowserWorker, pool_size);
    errdefer allocator.free(workers);

    const job_storage = try allocator.alloc(ScrapeSpec, pool_size * 4);
    errdefer allocator.free(job_storage);

    const result_storage = try allocator.alloc(ScrapeResult, pool_size * 4);
    errdefer allocator.free(result_storage);

    //@TODO: Switch to more robust system, right now just expects a simple host:port
    const separator = std.mem.findScalarLast(u8, endpoint, ':')
        orelse return error.MissingPort;

    const host = endpoint[0..separator];
    if (host.len == 0) return error.MissingHost;

    const port = try std.fmt.parseInt(
        u16,
        endpoint[separator + 1..],
        10,
    );

    var initialized: usize = 0;

    errdefer {
        for(workers[0..initialized]) |*worker| {
            worker.cdp.deinit();
        }
    }

    for (workers, 0..) |*worker, index| {
        worker.* = .{
            .id = index,
            .cdp = try CdpClient.connect(
                io,
                allocator,
                host,
                port,
            )
        };
        initialized += 1;
    }

    return .{
        .allocator = allocator,
        .io = io,
        .workers = workers,
        .jobs = .init(job_storage),
        .results = .init(result_storage),
        .job_storage = job_storage,
        .result_storage = result_storage
    };
}

pub fn start(self: *BrowserPool) !void {
    for (self.workers) |*worker| {
        try self.group.concurrent(self.io, BrowserWorker.run, .{
            worker,
            self.io,
            self.allocator,
            &self.jobs,
            // &self.results,
        });
    }
}

pub fn shutdown(self: *BrowserPool) !void {
    self.jobs.close(self.io);

    try self.group.await(self.io);

    self.results.close(self.io);

    for (self.workers) |*worker| {
        worker.cdp.deinit();
    }

    self.allocator.free(self.workers);
    self.allocator.free(self.job_storage);
    self.allocator.free(self.result_storage);
}
