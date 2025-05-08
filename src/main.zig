const std = @import("std");
const root = @import("root.zig");
const process = std.process;
const Allocator = std.mem.Allocator;
const log = std.log;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try generateCommit(allocator);
}

fn generateCommit(allocator: Allocator) !void {
    const git = root.Git.init(allocator);

    if (!try git.isGitRepo()) {
        std.log.err("Not a Git repository.", .{});
        return;
    }

    if (!try git.hasChanges()) {
        std.log.info("No changes to commit.", .{});
        return;
    }

    const files_to_stage = try git.filesToBeStaged();
    if (files_to_stage == null) {
        std.log.info("No changes to commit.", .{});
        return;
    }
    defer allocator.free(files_to_stage.?);

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    try stdout.print("Files to be staged:\n {s}\n", .{files_to_stage.?});
    try stdout.print("Stage these files? (y/n): ", .{});

    const confirm = try stdin.readUntilDelimiterOrEofAlloc(allocator, '\n', 10)
        orelse return error.InputFailed;
    defer allocator.free(confirm);

    const trimmed = std.mem.trim(u8, confirm, " \n");
    if (!std.mem.eql(u8, trimmed, "y") and !std.mem.eql(u8, trimmed, "yes")) {
        try stdout.print("Staging aborted.\n", .{});
        return;
    }

    const curr_branch = try git.currentBranch();
    if (std.mem.eql(u8, curr_branch, "main") or std.mem.eql(u8, curr_branch, "master")) {
        try git.createBranch("wip");
    }

    try git.stageFiles();
    try stdout.print("Files staged successfully.\n", .{});
}
