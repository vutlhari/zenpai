const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ExecResult = struct {
    exit_code: u8,
    stdout: []const u8,
    stderr: []const u8,
};

pub const Git = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) Git {
        return .{ .allocator = allocator };
    }

    pub fn isGitRepo(self: Git) !bool {
        const result = try exec(&[_][]const u8{ "git", "rev-parse", "--is-inside-work-tree" }, self.allocator);
        if (result.exit_code != 0) {
            return false;
        }

        return std.mem.eql(u8, std.mem.trim(u8, result.stdout, " \n"), "true");
    }

    pub fn hasChanges(self: Git) !bool {
        const result = try exec(&[_][]const u8{ "git", "status", "--porcelain" }, self.allocator);
        if (result.exit_code != 0) {
            return error.CommandFailed;
        }

        return result.stdout.len > 0;
    }

    pub fn currentBranch(self: Git) ![]const u8 {
        const result = try exec(&[_][]const u8{ "git", "rev-parse", "--abbrev-ref", "HEAD" }, self.allocator);
        if (result.exit_code != 0) {
            return error.CommandFailed;
        }

        return std.mem.trim(u8, result.stdout, " \n");
    }

    pub fn filesToBeStaged(self: Git) !?[]const u8 {
        const result = try exec(&[_][]const u8{ "git", "status", "--porcelain" }, self.allocator);
        if (result.exit_code != 0) {
            return error.CommandFailed;
        }

        if (result.stdout.len == 0) {
            return null;
        }

        return try self.allocator.dupe(u8, result.stdout);
    }

    pub fn stageFiles(self: Git) !void {
        const result = try exec(&[_][]const u8{ "git", "add", "." }, self.allocator);
        if (result.exit_code != 0) {
            std.log.err("Failed to stage files: {s}", .{result.stderr});
            return error.CommandFailed;
        }
    }

    pub fn commit(self: Git, commit_msg: []const u8) !void {
        const result = try exec(&[_][]const u8{ "git", "commit", "-m", commit_msg }, self.allocator);
        if (result.exit_code != 0) {
            std.log.err("Failed to commit: {s}", .{result.stderr});
            return error.CommandFailed;
        }
    }

    pub fn createBranch(self: Git, branch_name: []const u8) !void {
        const result = try exec(&[_][]const u8{ "git", "checkout", "-b", branch_name }, self.allocator);
        if (result.exit_code != 0) {
            std.log.err("Failed to create branch: {s}", .{result.stderr});
            return error.CommandFailed;
        }
    }

    pub fn getStagedDiff(self: Git) ![]const u8 {
        var args = std.ArrayList([]const u8).init(self.allocator);
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

        const diff_result = try exec(args.items, self.allocator);
        if (diff_result.exit_code != 0) {
            std.log.err("Failed to get staged diff: {s}", .{diff_result.stderr});
            return error.CommandFailed;
        }

        return try self.allocator.dupe(u8, diff_result.stdout);
    }
};

fn exec(argv: []const []const u8, allocator: Allocator) !ExecResult {
    var child = std.process.Child.init(argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    const stdout = try child.stdout.?.readToEndAlloc(allocator, std.math.maxInt(usize));
    const stderr = try child.stderr.?.readToEndAlloc(allocator, std.math.maxInt(usize));

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
