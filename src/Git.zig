const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log;

const Self = @This();

pub const ExecResult = struct {
    exit_code: u8,
    stdout: []const u8,
    stderr: []const u8,

    pub fn deinit(self: ExecResult, allocator: Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

alloc: Allocator,

pub fn init(allocator: Allocator) Self {
    return .{ .alloc = allocator };
}

pub fn isGitRepo(self: *Self) !bool {
    const result = try exec(&[_][]const u8{ "git", "rev-parse", "--is-inside-work-tree" }, self.alloc);
    defer result.deinit(self.alloc);

    if (result.exit_code != 0) {
        return false;
    }

    const trimmed_result = std.mem.trim(u8, result.stdout, &std.ascii.whitespace);
    return std.mem.eql(u8, trimmed_result, "true");
}

pub fn hasChanges(self: *Self) !bool {
    const result = try exec(&[_][]const u8{ "git", "status", "--porcelain" }, self.alloc);
    defer result.deinit(self.alloc);

    if (result.exit_code != 0) {
        return error.CommandFailed;
    }

    return result.stdout.len > 0;
}

pub fn currentBranch(self: *Self) ![]const u8 {
    const result = try exec(&[_][]const u8{ "git", "rev-parse", "--abbrev-ref", "HEAD" }, self.alloc);
    defer result.deinit(self.alloc);

    if (result.exit_code != 0) {
        return error.CommandFailed;
    }

    return std.mem.trim(u8, result.stdout, &std.ascii.whitespace);
}

pub fn filesToBeStaged(self: *Self) !?[]const u8 {
    const result = try exec(&[_][]const u8{ "git", "status", "--porcelain" }, self.alloc);
    defer result.deinit(self.alloc);

    if (result.exit_code != 0) {
        return error.CommandFailed;
    }

    if (result.stdout.len == 0) {
        return null;
    }

    return try self.alloc.dupe(u8, result.stdout);
}

pub fn stageFiles(self: *Self) !void {
    const result = try exec(&[_][]const u8{ "git", "add", "." }, self.alloc);
    defer result.deinit(self.alloc);

    if (result.exit_code != 0) {
        log.err("Failed to stage files: {s}", .{result.stderr});
        return error.CommandFailed;
    }
}

pub fn commit(self: *Self, commit_msg: []const u8) !void {
    const result = try exec(&[_][]const u8{ "git", "commit", "-m", commit_msg }, self.alloc);
    defer result.deinit(self.alloc);

    if (result.exit_code != 0) {
        log.err("Failed to commit: {s}", .{result.stderr});
        return error.CommandFailed;
    }
}

pub fn createBranch(self: *Self, branch_name: []const u8) !void {
    const result = try exec(&[_][]const u8{ "git", "checkout", "-b", branch_name }, self.alloc);
    defer result.deinit(self.alloc);

    if (result.exit_code != 0) {
        log.err("Failed to create branch: {s}", .{result.stderr});
        return error.CommandFailed;
    }
}

pub fn getStagedDiff(self: *Self) ![]const u8 {
    var args = std.ArrayList([]const u8).init(self.alloc);
    defer args.deinit();

    const default_excludes = [_][]const u8{
        ":(exclude)^package-lock.json",
        ":(exclude)^pnpm-lock.yaml",
        ":(exclude)^*.lock",
        ":(exclude)*.lockb",
        ":(exclude)*.gif",
        ":(exclude)*.png",
    };

    try args.appendSlice(&[_][]const u8{ "git", "diff", "--cached", "--" });
    try args.appendSlice(&default_excludes);

    const diff_result = try exec(args.items, self.alloc);
    if (diff_result.exit_code != 0) {
        log.err("Failed to get staged diff: {s}", .{diff_result.stderr});
        return error.CommandFailed;
    }

    return try self.alloc.dupe(u8, diff_result.stdout);
}

fn exec(argv: []const []const u8, alloc: Allocator) !ExecResult {
    var child = std.process.Child.init(argv, alloc);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    const stdout = try child.stdout.?.readToEndAlloc(alloc, std.math.maxInt(usize));
    const stderr = try child.stderr.?.readToEndAlloc(alloc, std.math.maxInt(usize));

    const term = try child.wait();

    const exit_code = switch (term) {
        .Exited => |code| code,
        else => return error.CommandFailed,
    };

    return ExecResult{
        .exit_code = exit_code,
        .stdout = stdout,
        .stderr = stderr,
    };
}
