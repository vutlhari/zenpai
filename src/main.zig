const std = @import("std");
const git = @import("git.zig");
const llm = @import("llm.zig");
const prompt = @import("prompt.zig");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const process = std.process;
const log = std.log;

const CommitMessage = struct {
    subject: []const u8,
    body: []const u8,
    footer: []const u8,

    pub fn deinit(self: CommitMessage, allocator: Allocator) void {
        allocator.free(self.subject);
        allocator.free(self.body);
        allocator.free(self.footer);
    }
};

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

    const diff = try gitClient.getStagedDiff();
    defer allocator.free(diff);

    const commitMsg = try generateCommitMsg(allocator, diff) orelse {
        std.log.info("No commit message generated.", .{});
        return;
    };
    defer commitMsg.deinit(allocator);

    try gitClient.commit(commitMsg.subject);
    try stdout.print("Changes committed successfully!\n\n  {s}\n", .{commitMsg.subject});
}

fn generateCommitMsg(allocator: Allocator, diff: []const u8) !?CommitMessage {
    var openai = try llm.Client.init(allocator, null);
    defer openai.deinit();

    const user_prompt = try std.fmt.allocPrint(allocator, "Here is the diff:\n\n{s}", .{diff});
    defer allocator.free(user_prompt);

    var messages = std.ArrayList(llm.Message).init(allocator);
    try messages.append(llm.Message.system(prompt.system));
    try messages.append(llm.Message.user(user_prompt));

    const payload = llm.ChatPayload{
        .model = "gpt-3.5-turbo",
        .messages = messages.items,
        .max_tokens = 1024,
        .temperature = 0.7,
    };

    var completion = try openai.chat(payload);
    defer completion.deinit();

    if (completion.value.choices.len == 0) {
        return null;
    }

    const msg_content = completion.value.choices[0].message.content;
    const parsed = std.json.parseFromSliceLeaky(CommitMessage, allocator, msg_content, .{
        .ignore_unknown_fields = true,
    }) catch |err| {
        std.log.err("Failed to parse JSON: {}", .{err});
        return null;
    };

    return CommitMessage{
        .subject = try allocator.dupe(u8, parsed.subject),
        .body = try allocator.dupe(u8, parsed.body),
        .footer = try allocator.dupe(u8, parsed.footer),
    };
}
