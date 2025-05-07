const std = @import("std");
const root = @import("root.zig");
const process = std.process;
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip the program name
    _ = args.next();

    const git_check = [_][]const u8{ "git", "rev-parse", "--is-inside-work-tree" };
    if (!try root.exec(&git_check, allocator, .IgnoreOutput)) {
        return error.NotGitRepository;
    }

    const git_status = [_][]const u8{ "git", "status", "--porcelain" };
    if (!try root.exec(&git_status, allocator, .CaptureOutput)) {
        return error.CommandFailed;
    }

    const git_add = [_][]const u8{ "git", "add", "." };
    if (!try root.exec(&git_add, allocator, .CaptureOutput)) {
        return error.CommandFailed;
    }
}
