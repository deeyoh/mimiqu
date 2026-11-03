const JavaScriptEmbedStep = @This();

const std = @import("std");
const Step = std.Build.Step;
const LazyPath = std.Build.LazyPath;

pub const JsFile = struct {
    name: []const u8,
    path: LazyPath,
};

step: *Step,
js_files: []const JsFile,

pub const Options = struct {
    /// The name of the directory to search for TypeScript files
    directory: LazyPath,

    /// The name of the TypeScript files to compile into JavaScript
    files: []const []const u8,

    /// The directory to place the generated JavaScript files
    out_dir: []const u8,
};

/// Create a step to generate embeddle JavaScript files from TypeScript
pub fn create(b: *std.Build, opts: Options) *JavaScriptEmbedStep {
    const self = b.allocator.create(JavaScriptEmbedStep) catch @panic("OOM");
    const js_files = b.allocator.alloc(JsFile, opts.files.len) catch @panic("OOM");

    self.* = .{ 
        .step = b.step("generate-js", "Compile TypeScript into JavaScript files"),
        .js_files = js_files
    };

    for (opts.files, 0..) |file_name, i| {
        const compile_ts = b.addSystemCommand(&.{ "tsc", "--target", "ES2022", "--module", "es2022" });

        compile_ts.addFileArg(opts.directory.path(b, file_name));

        const js_name = b.fmt("{s}.js", .{std.fs.path.stem(file_name)});

        compile_ts.addArg("--outDir");
        const output_dir = compile_ts.addOutputDirectoryArg("js");
        const output_path = output_dir.path(b, js_name);

        js_files[i] = .{
            .name = js_name,
            .path = output_path,
        };

        const install_step = b.addInstallFileWithDir(
            output_path,
            .prefix,
            b.pathJoin(&.{ opts.out_dir, js_name }),
        );

        self.step.dependOn(&install_step.step);
    }
    // b.getInstallStep().dependOn(self.step);
    return self;
}
