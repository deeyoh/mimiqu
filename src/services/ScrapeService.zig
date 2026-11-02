const ScrapeService = @This();

const std = @import("std");
const proto = @import("mimiqu_proto");
const build_options = @import("build_options");
const grpc = @import("grpc_lite");
const grpc_pb = @import("grpc_lite_protobuf");
const BrowserPool = @import("../BrowserPool.zig");

const errors = @import("../errors.zig");

pub const Error = 
    errors.AppError ||
    std.Io.QueueClosedError ||
    std.Io.Cancelable;

pub const Api = proto.ScraperService(ScrapeService, Error);
pub const Registration = grpc_pb.ServiceRegistration(Api);

allocator: std.mem.Allocator,
pool: *BrowserPool,

pub fn initAndRegister(
    self: *ScrapeService,
    allocator: std.mem.Allocator,
    server: *grpc.Server,
    registration: *Registration,
) !void {
    registration.* = Registration.init(
        allocator,
        self,
        .{ .Scrape = ScrapeService.scrape },
        .{},
    );
    errdefer registration.deinit();

    try registration.register(server);
}

//submits a job to the pool, where it is picked up by the internal
//browser worker
pub fn scrape(
    self: *ScrapeService,
    request: proto.ScrapeRequest
) Error!proto.ScrapeResponse {
    //validate gRPC `ScrapeRequest`
    //
    //and then
    // if (request.fields.len != 0)
    // const job_url = try self.
    std.log.info("scrape request received: id={d}, url={s}\n", .{request.id, request.url});

    const job_url = try self.pool.allocator.dupe(u8, request.url);
    errdefer self.pool.allocator.free(job_url);

    const response_url = try self.allocator.dupe(u8, request.url);
    errdefer self.allocator.free(response_url);

    //@TODO: Temp marker
    const data_json = try self.allocator.dupe(u8, "{}");
    errdefer self.allocator.free(data_json);

    try self.pool.jobs.putOne(self.pool.io, .{
        .id = request.id,
        .url = job_url,
        .fields = &.{},
        .timeout_ms = request.timeout_ms,
    });

    return .{
        .url = response_url,
        .data_json = data_json,
    };
}

