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

    try gitClient.stageFiles();
    try stdout.print("Files staged successfully.\n", .{});

    const diff = try gitClient.getStagedDiff();
    defer allocator.free(diff);

    const system_msg =
        \\You are a helpful assistant specializing in writing clear and informative Git commit messages using the conventional style
        \\Based on the given code changes or context, generate exactly 1 conventional Git commit message based on the following guidelines.
        \\1. Message Language: en
        \\2. Format: follow the conventional Commits format:
        \\   <type>(<optional scope>): <description>
        \\
        \\   [optional body]
        \\
        \\   [optional footer(s)]
        \\3. Types: use one of the following types:
        \\   docs: Documentation only changes
        \\   style: Changes that do not affect the meaning of the code (white-space, formatting, missing semi-colons, etc)
        \\   refactor: A code change that neither fixes a bug nor adds a feature
        \\   perf: A code change that improves performance
        \\   test: Adding missing tests or correcting existing tests
        \\   build: Changes that affect the build system or external dependencies
        \\   ci: Changes to CI configuration files, scripts
        \\   chore: Other changes that don't modify src or test files
        \\   revert: Reverts a previous Commits
        \\   feat: A new feature
        \\   fix: A bug fix
        \\4. Guidelines for writing commit messages:
        \\  - Be specific about what changes were made
        \\  - Use imperative mood ("add feature" not "added feature")
        \\  - Keep subject line under 50 characters
        \\  - Do not end the subject line with a period
        \\  - Use the body to explain what and why vs. how
        \\5. Focus on:
        \\  - What problem this commit solves
        \\  - Why this change was necessary
        \\  - Any important technical details
        \\6. Exclude anything unnecessary such as translation or implementation details.
    ;

    const prompt = try std.fmt.allocPrint(allocator, "Here is the diff:\n\n{s}", .{diff});
    defer allocator.free(prompt);

    var messages = std.ArrayList(llm.Message).init(allocator);
    try messages.append(llm.Message.system(system_msg));
    try messages.append(llm.Message.user(prompt));

    const payload = llm.ChatPayload{
        .model = "gpt-4o",
        .messages = messages.items,
        .max_tokens = 1000,
        .temperature = 0.2,
    };

    var completion = try openai.chat(payload, false);
    defer completion.deinit();

    if (completion.value.choices.len > 0) {
        const message_content = completion.value.choices[0].message.content;
        try stdout.print("Completion: {s}\n", .{message_content});
    } else {
        try stdout.print("No completion choices received.\n", .{});
    }
}
