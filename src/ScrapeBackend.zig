const std = @import("std");
const proto = @import("mimiqu_proto");

const CdpClient = @import("CdpClient.zig");
const ScrapeSpec = @import("ScrapeSpec.zig");

const wait_ready_js = @embedFile("wait-ready.js");
const extract_js = @embedFile("extract.js");

pub fn scrape(
    cdp: *CdpClient,
    allocator: std.mem.Allocator,
    spec: ScrapeSpec,
) !proto.ScrapeResponse {
    var navigation = try cdp.send("Page.navigate", .{
        .url = spec.url,
    });
    defer navigation.deinit();

    if (navigation.value != .object)
        return error.InvalidCdpResponse;

    const navigation_result = navigation.value.object.get("result") orelse
        return error.InvalidCdpResponse;
    if (navigation_result != .object)
        return error.InvalidCdpResponse;
    if (navigation_result.object.contains("errorText"))
        return error.NavigationFailed;

    const timeout_ms: u32 = if (spec.timeout_ms == 0)
        30_000
    else
        spec.timeout_ms;

    const readiness_expression = try std.fmt.allocPrint(
        allocator,
        "(() => {{\n{s}\nreturn waitReady({d});\n}})()",
        .{ wait_ready_js, timeout_ms },
    );
    defer allocator.free(readiness_expression);

    var readiness = try cdp.send("Runtime.evaluate", .{
        .expression = readiness_expression,
        .awaitPromise = true,
        .returnByValue = true,
    });
    defer readiness.deinit();

    if (readiness.value != .object)
        return error.InvalidCdpResponse;

    const readiness_result = readiness.value.object.get("result") orelse
        return error.InvalidCdpResponse;
    if (readiness_result != .object)
        return error.InvalidCdpResponse;
    if (readiness_result.object.contains("exceptionDetails"))
        return error.JavaScriptException;

    const readiness_object = readiness_result.object.get("result") orelse
        return error.InvalidCdpResponse;
    if (readiness_object != .object)
        return error.InvalidCdpResponse;

    const ready = readiness_object.object.get("value") orelse
        return error.InvalidCdpResponse;
    if (ready != .bool)
        return error.InvalidCdpResponse;
    if (!ready.bool)
        return error.Timeout;

    const JsField = struct {
        name: []const u8,
        selector: []const u8,
        kind: []const u8,
        attribute: ?[]const u8,
        required: bool,
    };

    const fields = try allocator.alloc(JsField, spec.fields.len);
    defer allocator.free(fields);

    for (spec.fields, fields) |source, *destination| {
        destination.* = .{
            .name = source.name,
            .selector = source.selector,
            .kind = switch (source.extraction) {
                .text => "text",
                .html => "html",
                .attribute => "attribute",
            },
            .attribute = switch (source.extraction) {
                .attribute => |name| name,
                else => null,
            },
            .required = source.required,
        };
    }

    const fields_json = try std.json.Stringify.valueAlloc(allocator, fields, .{});
    defer allocator.free(fields_json);

    const extraction_expression = try std.fmt.allocPrint(
        allocator,
        "(() => {{\n{s}\nreturn extract({s});\n}})()",
        .{ extract_js, fields_json },
    );
    defer allocator.free(extraction_expression);

    var extraction = try cdp.send("Runtime.evaluate", .{
        .expression = extraction_expression,
        .returnByValue = true,
    });
    defer extraction.deinit();

    if (extraction.value != .object)
        return error.InvalidCdpResponse;

    const extraction_result = extraction.value.object.get("result") orelse
        return error.InvalidCdpResponse;
    if (extraction_result != .object)
        return error.InvalidCdpResponse;
    if (extraction_result.object.contains("exceptionDetails"))
        return error.JavaScriptException;

    const extraction_object = extraction_result.object.get("result") orelse
        return error.InvalidCdpResponse;
    if (extraction_object != .object)
        return error.InvalidCdpResponse;

    const data = extraction_object.object.get("value") orelse
        return error.InvalidCdpResponse;
    if (data != .string)
        return error.InvalidCdpResponse;

    const data_json = try allocator.dupe(u8, data.string);
    errdefer allocator.free(data_json);

    return .{
        .url = try allocator.dupe(u8, spec.url),
        .data_json = data_json,
    };
}
