const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = b.addOptions();
    const version = getVersion(b.allocator);
    options.addOption([]const u8, "version", version);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addOptions("build_options", options);

    const exe = b.addExecutable(.{
        .name = "zenpai",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn getVersion(allocator: std.mem.Allocator) []const u8 {
    const content = std.fs.cwd().readFileAlloc(allocator, "build.zig.zon", 1024) catch return "unknown";
    defer allocator.free(content);
    
    const needle = ".version = \"";
    const start = std.mem.indexOf(u8, content, needle) orelse return "unknown";
    const version_start = start + needle.len;
    const end = std.mem.indexOfScalarPos(u8, content, version_start, '"') orelse return "unknown";
    
    return allocator.dupe(u8, content[version_start..end]) catch "unknown";
}
