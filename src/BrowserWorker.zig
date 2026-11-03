const BrowserWorker = @This();

const std = @import("std");
const proto = @import("mimiqu_proto");
const CdpClient = @import("CdpClient.zig");
const ScrapeJob = @import("ScrapeJob.zig");
const ScrapeSpec = @import("ScrapeSpec.zig");

/// The backend must finish all CDP work before returning and enforce browser
/// timeouts. Response allocations may use the supplied per-job allocator.
pub const ScrapeFn = *const fn (
    *CdpClient,
    std.mem.Allocator,
    ScrapeSpec,
) anyerror!proto.ScrapeResponse;

id: usize,
cdp: CdpClient,
scrape_fn: ?ScrapeFn = null,

pub fn run(
    self: *BrowserWorker,
    io: std.Io,
    pool_allocator: std.mem.Allocator,
    jobs: *std.Io.Queue(*ScrapeJob),
) void {
    while (true) {
        const job = jobs.getOne(io) catch break;
        defer job.destroy(pool_allocator);

        if (job.server_call.isTerminal() or job.server_call.isCancelled())
            continue;

        self.process(job) catch |err| {
            std.log.warn("[Worker {d}] job {d} failed: {s}", .{
                self.id, job.spec.?.id, @errorName(err),
            });

            switch (err) {
                error.ScrapeNotImplemented => job.fail(.unimplemented, "CDP scraping is not implemented"),
                error.Timeout => job.fail(.deadline_exceeded, "scrape timed out"),
                error.OutOfMemory, error.WouldBlock => job.fail(.resource_exhausted, "response resources exhausted"),
                else => job.fail(.internal, "scrape failed"),
            }
        };
    }
}

fn process(self: *BrowserWorker, job: *ScrapeJob) !void {
    const scrape = self.scrape_fn orelse return error.ScrapeNotImplemented;
    const allocator = job.arena.allocator();
    const spec = job.spec.?;

    std.log.info("[Worker {d}] starting job {d}: {s}", .{ self.id, spec.id, spec.url });
    const response = try scrape(&self.cdp, allocator, spec);

    // Cancellation can still race with send/finish; their errors are handled
    // by the caller. These checks only avoid unnecessary encoding.
    if (job.server_call.isTerminal() or job.server_call.isCancelled())
        return;

    var writer: std.Io.Writer.Allocating = .init(allocator);
    defer writer.deinit();
    try response.encode(&writer.writer, allocator);

    // These commands are copied/queued for the reactor, not written directly
    // to its socket from this worker. WouldBlock fails rather than polling.
    try job.server_call.send(writer.written(), .{});
    try job.server_call.finish(.{ .code = .ok }, &.{});
}
