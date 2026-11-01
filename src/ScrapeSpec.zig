const ScrapeSpec = @This();

const std = @import("std");

id: u32,
url: []const u8,
fields: []const ExtractionField,
timeout_ms: u32,

pub const ExtractionField = struct {
    name: []const u8,
    selector: []const u8,
    extraction: Extraction,
    required: bool,
};

/// Enforces a valid proto contract at the domain level
/// by preventing invalid logic combinations. For example,
/// cannot send `EXTRACTION_TYPE_ATTRIBUTE` with an empty
/// attribute, or `EXTRACTGION_TYPE_TEXT` with an `href` attribute
pub const Extraction = union(enum) {
    text,
    html,
    attribute: []const u8,
};
