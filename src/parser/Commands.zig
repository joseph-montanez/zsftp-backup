const std = @import("std");
const string = @import("string");

const testing = std.testing;

pub const FileInfo = struct {
    permissions: []const u8,
    owner: []const u8,
    group: []const u8,
    size: usize,
    timestamp: []const u8,
    name: []const u8,
    is_dir: bool,
    path: []const u8,
};

pub fn listing(allocator: std.mem.Allocator, str: *std.ArrayList(u8), files: *std.ArrayList(FileInfo)) !void {
    var lines = std.mem.splitScalar(u8, str.items, '\n');

    while (lines.next()) |line| {
        try listingParseLine(allocator, line, files);
    }
}

pub fn listingParseLine(_: std.mem.Allocator, line: []const u8, files: *std.ArrayList(FileInfo)) !void {
    var it = std.mem.splitSequence(u8, line, "\\0");

    const permissions = it.next() orelse return; // 0
    const is_dir = permissions.len > 0 and permissions[0] == 'd';

    // Ignore hardlinks for now
    _ = it.next() orelse return; // 1

    const owner = it.next() orelse return; // 2
    const group = it.next() orelse return; // 3
    const size_str = it.next() orelse return; // 4
    const size = try std.fmt.parseInt(usize, size_str, 10);

    const timestamp = it.next() orelse return; // 5

    const path = it.rest(); // 6

    // This has to reallocate the data for each item because the
    // `raw_data` is deallocated
    try files.append(FileInfo{
        .permissions = permissions,
        // .hard_links = hard_links, // Store the hard link count
        .owner = owner,
        .group = group,
        .size = size,
        .timestamp = timestamp,
        .name = path,
        .is_dir = is_dir,
        .path = path,
    });
}

test "read file listing with `ls -la`" {
    const allocator = testing.allocator;

    const data =
        \\total 8
        \\drwxr-xr-x\07\0testuser\0users\0224\0Jan 18 02:08\0.
        \\drwxr-xr-x\01\0root\0root\04096\0Jan 16 07:18\0..
        \\drwx------\03\0testuser\0users\096\0Jan 16 19:17\0.ssh
        \\drwxr-xr-x\04\0testuser\0users\0128\0Jan 16 19:17\0logs
        \\drwxr-xr-x\08\0testuser\0users\0256\0Jan 16 19:17\0ssh_host_keys
        \\drwxr-x---\03\0root\0users\096\0Jan 18 02:08\0sshd
        \\-rw-r--r--\01\0testuser\0users\04\0Jan 18 02:08\0sshd.pid
    ;

    var dataString = std.ArrayList(u8).init(allocator);
    try dataString.appendSlice(data);
    defer dataString.deinit();

    var files = std.ArrayList(FileInfo).init(allocator);
    try listing(allocator, &dataString, &files);
    defer files.deinit();

    const expected_files = [_]FileInfo{
        .{ .permissions = "drwxr-xr-x", .owner = "testuser", .group = "users", .size = 224, .timestamp = "Jan 18 02:08", .name = ".", .is_dir = true, .path = "." },
        .{ .permissions = "drwxr-xr-x", .owner = "root", .group = "root", .size = 4096, .timestamp = "Jan 16 07:18", .name = "..", .is_dir = true, .path = ".." },
        .{ .permissions = "drwx------", .owner = "testuser", .group = "users", .size = 96, .timestamp = "Jan 16 19:17", .name = ".ssh", .is_dir = true, .path = ".ssh" },
        .{ .permissions = "drwxr-xr-x", .owner = "testuser", .group = "users", .size = 128, .timestamp = "Jan 16 19:17", .name = "logs", .is_dir = true, .path = "logs" },
        .{ .permissions = "drwxr-xr-x", .owner = "testuser", .group = "users", .size = 256, .timestamp = "Jan 16 19:17", .name = "ssh_host_keys", .is_dir = true, .path = "ssh_host_keys" },
        .{ .permissions = "drwxr-x---", .owner = "root", .group = "users", .size = 96, .timestamp = "Jan 18 02:08", .name = "sshd", .is_dir = true, .path = "sshd" },
        .{ .permissions = "-rw-r--r--", .owner = "testuser", .group = "users", .size = 4, .timestamp = "Jan 18 02:08", .name = "sshd.pid", .is_dir = false, .path = "sshd.pid" },
    };

    try testing.expectEqual(@as(usize, expected_files.len), files.items.len);

    for (expected_files, files.items) |expected, actual| {
        try testing.expect(std.mem.eql(u8, expected.permissions, actual.permissions));
        try testing.expect(std.mem.eql(u8, expected.owner, actual.owner));
        try testing.expect(std.mem.eql(u8, expected.group, actual.group));
        try testing.expectEqual(expected.size, actual.size);
        try testing.expect(std.mem.eql(u8, expected.timestamp, actual.timestamp));
        try testing.expect(std.mem.eql(u8, expected.name, actual.name));
        try testing.expectEqual(expected.is_dir, actual.is_dir);
        try testing.expect(std.mem.eql(u8, expected.path, actual.path));
    }
}

test "listing - single line japanese text" {
    const allocator = testing.allocator;

    const data: *const [64:0]u8 =
        "-rw-r--r--\\01\\0testuser\\0users\\04\\01737416842\\07禁記どク.zip";

    var dataString = std.ArrayList(u8).init(allocator);
    try dataString.appendSlice(data);
    defer dataString.deinit();

    var files = std.ArrayList(FileInfo).init(allocator);
    defer files.deinit();
    // defer listingDeinit(allocator, &files);

    try listingParseLine(allocator, dataString.items, &files);

    const expected_files = [_]FileInfo{
        .{ .permissions = "-rw-r--r--", .owner = "testuser", .group = "users", .size = 4, .timestamp = "1737416842", .name = "7禁記どク.zip", .is_dir = false, .path = "7禁記どク.zip" },
    };

    try testing.expectEqual(@as(usize, expected_files.len), files.items.len);

    for (expected_files, files.items) |expected, actual| {
        try testing.expect(std.mem.eql(u8, expected.permissions, actual.permissions));
        try testing.expect(std.mem.eql(u8, expected.owner, actual.owner));
        try testing.expect(std.mem.eql(u8, expected.group, actual.group));
        try testing.expectEqual(expected.size, actual.size);
        try testing.expect(std.mem.eql(u8, expected.timestamp, actual.timestamp));
        try testing.expect(std.mem.eql(u8, expected.name, actual.name));
        try testing.expectEqual(expected.is_dir, actual.is_dir);
    }
}

test "Test for \\0 in the filename" {
    const allocator = testing.allocator;

    const data =
        "-rw-r--r--\\01\\0testuser\\0users\\04\\01737416842\\07禁記どク.\\0zip";

    var dataString = std.ArrayList(u8).init(allocator);
    try dataString.appendSlice(data);
    defer dataString.deinit();

    var files = std.ArrayList(FileInfo).init(allocator);
    defer files.deinit();
    // defer listingDeinit(allocator, &files);

    try listingParseLine(allocator, dataString.items, &files);

    const expected_files = [_]FileInfo{
        .{ .permissions = "-rw-r--r--", .owner = "testuser", .group = "users", .size = 4, .timestamp = "1737416842", .name = "7禁記どク.\\0zip", .is_dir = false, .path = "7禁記どク.\\0zip" },
    };

    try testing.expectEqual(@as(usize, expected_files.len), files.items.len);

    for (expected_files, files.items) |expected, actual| {
        try testing.expect(std.mem.eql(u8, expected.permissions, actual.permissions));
        try testing.expect(std.mem.eql(u8, expected.owner, actual.owner));
        try testing.expect(std.mem.eql(u8, expected.group, actual.group));
        try testing.expectEqual(expected.size, actual.size);
        try testing.expect(std.mem.eql(u8, expected.timestamp, actual.timestamp));
        try testing.expect(std.mem.eql(u8, expected.name, actual.name));
        try testing.expectEqual(expected.is_dir, actual.is_dir);
    }
}
