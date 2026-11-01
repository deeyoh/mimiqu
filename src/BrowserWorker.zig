const BrowserWorker = @This();

const std = @import("std");
const CdpClient = @import("CdpClient.zig");
const ScrapeSpec = @import("ScrapeSpec.zig");
const ScrapeResult = @import("ScrapeResult.zig");

id: usize,
cdp: CdpClient,

pub fn run(
    self: *BrowserWorker,
    io: std.Io,
    jobs: *std.Io.Queue(ScrapeSpec),
) void {
    while (true) {
        const job = jobs.getOne(io) catch break;
        std.log.info("[Worker {d}] starting job {d}\n", .{ self.id, job.id });
        self.scrape(job.url);
    }
}

fn scrape(
    self: *BrowserWorker,
    url: []const u8,
) void {
    _ = self;
    std.log.info("perfoming scrape on URL: {s}\n", .{url});
}
