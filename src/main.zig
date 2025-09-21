const std = @import("std");
const Git = @import("Git.zig");
const OpenAI = @import("OpenAI.zig");
const prompt = @import("prompt.zig");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const process = std.process;
const log = std.log;

const CommitMessage = struct {
    subject: []const u8,
    body: []const u8,
    footer: []const u8,

    fn deinit(self: CommitMessage, allocator: Allocator) void {
        allocator.free(self.subject);
        allocator.free(self.body);
        allocator.free(self.footer);
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            printVersion();
            return;
        }
    }

    if (comptime builtin.mode == .Debug) {
        log.warn("This is a debug build. Performance will be very poor.", .{});
        log.warn("You should only use a debug build for developing Zenpai.", .{});
        log.warn("Otherwise, please rebuild in a release mode.\n", .{});
    }

    try generateCommit(allocator);
}

fn printVersion() void {
    const version = @import("build_options").version;
    std.debug.print("zenpai v{s}\n", .{version});
}

fn generateCommit(allocator: Allocator) !void {
    var git: Git = .init(allocator);

    if (!try git.isGitRepo()) {
        log.err("Not a Git repository.", .{});
        return;
    }

    if (!try git.hasChanges()) {
        log.info("No changes to commit.", .{});
        return;
    }

    const files_to_stage = try git.filesToBeStaged();
    if (files_to_stage == null) {
        log.info("No changes to commit.", .{});
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

    const trimmed_confirm = std.mem.trim(u8, confirm, &std.ascii.whitespace);
    if (!std.mem.eql(u8, trimmed_confirm, "y") and !std.mem.eql(u8, trimmed_confirm, "yes")) {
        try stdout.print("Staging aborted.\n", .{});
        return;
    }

    const curr_branch = try git.currentBranch();
    if (std.mem.eql(u8, curr_branch, "main") or std.mem.eql(u8, curr_branch, "master")) {
        try git.createBranch("wip");
    }

    try git.stageFiles();
    try stdout.print("Files staged successfully.\n", .{});

    const diff = try git.getStagedDiff();
    defer allocator.free(diff);

    const commitMsg = try generateCommitMsg(allocator, diff) orelse {
        log.info("No commit message generated.", .{});
        return;
    };
    defer commitMsg.deinit(allocator);

    try git.commit(commitMsg.subject);
    try stdout.print("Changes committed successfully!\n\n  {s}\n", .{commitMsg.subject});
}

fn generateCommitMsg(allocator: Allocator, diff: []const u8) !?CommitMessage {
    var openai: OpenAI = try .init(allocator, null);
    defer openai.deinit();

    const user_prompt = try std.fmt.allocPrint(allocator, "Here is the diff:\n\n{s}", .{diff});
    defer allocator.free(user_prompt);

    var messages = std.ArrayList(OpenAI.Message).init(allocator);
    try messages.append(OpenAI.Message.system(prompt.system));
    try messages.append(OpenAI.Message.user(user_prompt));

    const payload = OpenAI.ChatPayload{
        .model = "gpt-4o-mini",
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
        log.err("Failed to parse JSON: {}", .{err});
        return null;
    };

    return CommitMessage{
        .subject = try allocator.dupe(u8, parsed.subject),
        .body = try allocator.dupe(u8, parsed.body),
        .footer = try allocator.dupe(u8, parsed.footer),
    };
}
