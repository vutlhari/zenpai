const std = @import("std");
const git = @import("git.zig");
const builtin = @import("builtin");
const process = std.process;
const Allocator = std.mem.Allocator;
const log = std.log;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    if (comptime builtin.mode == .Debug) {
        std.log.warn("This is a debug build. Performance will be very poor.", .{});
        std.log.warn("You should only use a debug build for developing Zenpai.", .{});
        std.log.warn("Otherwise, please rebuild in a release mode.\n", .{});
    }

    try generateCommit(allocator);
}

fn generateCommit(allocator: Allocator) !void {
    const gitClient = git.Git.init(allocator);

    if (!try gitClient.isGitRepo()) {
        std.log.err("Not a Git repository.", .{});
        return;
    }

    if (!try gitClient.hasChanges()) {
        std.log.info("No changes to commit.", .{});
        return;
    }

    const files_to_stage = try gitClient.filesToBeStaged();
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

    const curr_branch = try gitClient.currentBranch();
    if (std.mem.eql(u8, curr_branch, "main") or std.mem.eql(u8, curr_branch, "master")) {
        try gitClient.createBranch("wip");
    }

    try gitClient.stageFiles();
    try stdout.print("Files staged successfully.\n", .{});
}
