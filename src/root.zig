const std = @import("std");
const Allocator = std.mem.Allocator;

pub const OutputMode = enum {
    CaptureOutput,
    IgnoreOutput,
};

pub fn exec(argv: []const []const u8, allocator: Allocator, mode: OutputMode) !bool {
    var child = std.process.Child.init(argv, allocator);

    switch (mode) {
        .IgnoreOutput => {
            child.stdout_behavior = .Ignore;
            child.stderr_behavior = .Ignore;
        },
        .CaptureOutput => {},
    }

    try child.spawn();
    const exit_status = try child.wait();

    switch (exit_status) {
        .Exited => |code| {
            return code == 0;
        },
        else => return error.CommandFailed,
    }
}
