const std = @import("std");
const git = @import("git.zig");
const llm = @import("llm.zig");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const process = std.process;
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
    var openai = try llm.Client.init(allocator, null);
    defer openai.deinit();

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

    var messages = std.ArrayList(llm.Message).init(allocator);
    try messages.append(llm.Message.system("You are a helpful assistant"));
    try messages.append(llm.Message.user("Generate a simple commit message"));

    const payload = llm.ChatPayload{
        .model = "gpt-4o",
        .messages = messages.items,
        .max_tokens = 1000,
        .temperature = 0.2,
    };

    var completion = try openai.chat(payload, false);
    defer completion.deinit();

    // Print the completion content
    if (completion.value.choices.len > 0) {
        const message_content = completion.value.choices[0].message.content;
        try stdout.print("Completion: {s}\n", .{message_content});
    } else {
        try stdout.print("No completion choices received.\n", .{});
    }

    try gitClient.stageFiles();
    try stdout.print("Files staged successfully.\n", .{});
}
