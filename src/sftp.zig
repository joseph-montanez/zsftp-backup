const std = @import("std");
const builtin = @import("builtin");
const parser = @import("parser/Commands.zig");
const native_os = builtin.os.tag;
const c = @cImport({
    if (native_os == .windows) {
        // Cannot import windows.h, cause other issues
        @cDefine("MIDL_INTERFACE", "struct");
    }
    @cInclude("libssh2.h");
    @cInclude("libssh2_sftp.h");
});

var stdout_mutex = std.Thread.Mutex{};

pub inline fn fileExistsAndReadable(path: []const u8) bool {
    var dir = std.fs.cwd();

    dir.access(path, .{ .mode = .read_only }) catch {
        return false;
    };

    return true;
}

pub fn handshake(session: *c.LIBSSH2_SESSION, stream: std.net.Stream) !c_int {
    const stdout = std.io.getStdOut().writer();

    // Start the SSH session
    var err_msg: [*c]u8 = null;
    var err_len: c_int = 0;
    const err_code = c.libssh2_session_handshake(session, if (native_os == .windows)
        @intFromPtr(stream.handle) // Windows: SOCKET  UINT_PTR (c_ulonglong)
    else
        @intCast(stream.handle) // POSIX: fd_t  c_int
    );

    // const err_code = c.libssh2_session_handshake(session, stream.handle);
    if (err_code != 0) {
        _ = c.libssh2_session_last_error(session, &err_msg, &err_len, 0);
        try stdout.print("SSH session handshake failed ({}): {s}\n", .{ err_code, err_msg });
    }

    return err_code;
}

pub fn authorize(
    session: *c.LIBSSH2_SESSION,
    username: []const u8,
    password: []const u8,
    private_key: []const u8,
    public_key: []const u8,
) !i32 {
    const stdout = std.io.getStdOut().writer();
    var is_auth: i32 = 0;

    if (private_key.len > 0) {
        if (std.mem.indexOf(u8, private_key, "embed://")) |is_embed| {
            if (is_embed >= 0) {
                const embedded_private_key = private_key[8..];
                const embedded_public_key = public_key[8..];
                is_auth = c.libssh2_userauth_publickey_frommemory(
                    session,
                    username.ptr,
                    @intCast(username.len),
                    embedded_public_key.ptr,
                    @intCast(embedded_public_key.len),
                    embedded_private_key.ptr,
                    @intCast(embedded_private_key.len),
                    null, // No passphrase
                );
            } else {
                is_auth = c.libssh2_userauth_publickey_fromfile_ex(
                    session,
                    username.ptr,
                    @intCast(username.len),
                    public_key.ptr,
                    private_key.ptr,
                    null, // No passphrase
                );
            }
        } else {
            is_auth = c.libssh2_userauth_publickey_fromfile_ex(
                session,
                username.ptr,
                @intCast(username.len),
                public_key.ptr,
                private_key.ptr,
                null, // No passphrase
            );
        }
    } else {
        is_auth = c.libssh2_userauth_password_ex(
            session,
            username.ptr,
            @intCast(username.len),
            password.ptr,
            @intCast(password.len),
            null,
        );
    }

    if (is_auth == c.LIBSSH2_ERROR_ALLOC) {
        try stdout.print("Internal memory allocation errror\n", .{});
    } else if (is_auth == c.LIBSSH2_ERROR_SOCKET_SEND) {
        try stdout.print("Unable to send data on socket\n", .{});
    } else if (is_auth == c.LIBSSH2_ERROR_SOCKET_TIMEOUT) {
        try stdout.print("Socket timeout before authorization\n", .{});
    } else if (is_auth == c.LIBSSH2_ERROR_PUBLICKEY_UNVERIFIED) {
        try stdout.print("Public key is unverified: {s}\n", .{public_key});
    } else if (is_auth == c.LIBSSH2_ERROR_AUTHENTICATION_FAILED) {
        try stdout.print("The public key was not accepted and failed authorization\n", .{});
    }

    if (is_auth != 0) {
        return error.AuthenticationFailed;
    }

    return is_auth;
}

pub const WorkerContext = struct {
    queue: *std.ArrayList(parser.FileInfo),
    lock: *std.Thread.Mutex,
    cond: *std.Thread.Condition,
    done: *std.atomic.Value(bool),
};

pub fn downloadFilesQueue(
    context: *WorkerContext,
    server_addr: std.net.Address,
    username: []const u8,
    password: []const u8,
    public_key: []const u8,
    private_key: []const u8,
    copy_to: []const u8,
    dry_run: bool,
) !void {
    const thread_id = std.Thread.getCurrentId();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var gpa_allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const stdout = std.io.getStdOut().writer();
    var arena = std.heap.ArenaAllocator.init(gpa_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const session: ?*c.LIBSSH2_SESSION = c.libssh2_session_init_ex(null, null, null, null);
    if (session == null) return error.SessionInitFailed;
    defer _ = c.libssh2_session_free(session);

    _ = c.libssh2_session_flag(session, c.LIBSSH2_FLAG_COMPRESS, 1);
    const stream: std.net.Stream = try std.net.tcpConnectToAddress(server_addr);
    defer stream.close();

    const err_code = try handshake(session.?, stream);
    if (err_code != 0) return error.HandshakeFailed;

    const is_auth = try authorize(session.?, username, password, private_key, public_key);
    if (is_auth != 0) return error.AuthenticationFailed;

    const sftp_session: ?*c.LIBSSH2_SFTP = c.libssh2_sftp_init(session);
    if (sftp_session == null) return error.SFTPInitFailed;

    const buffer_size = 1024 * 256;
    var buffer = try gpa_allocator.alloc(u8, buffer_size);
    defer gpa_allocator.free(buffer);

    const trimmed_copy_to_path: []const u8 = std.mem.trimLeft(u8, copy_to, "/");

    var path_map = std.StringHashMap(bool).init(allocator);
    defer path_map.deinit();

    while (true) {
        context.lock.lock();
        while (context.queue.items.len == 0 and !context.done.load(.acquire)) {
            context.cond.wait(context.lock);
        }

        if (context.queue.items.len == 0 and context.done.load(.acquire)) {
            context.lock.unlock();
            break;
        }

        const file = context.queue.popOrNull() orelse {
            context.lock.unlock();
            continue;
        };
        context.lock.unlock();

        if (file.is_dir) {
            if (!dry_run) {
                try std.fs.cwd().makePath(copy_to);
            }
            continue;
        }

        var trimmed_file_path: []const u8 = std.mem.trimLeft(u8, file.path, "/.");
        if (std.mem.startsWith(u8, trimmed_file_path, "/")) {
            trimmed_file_path = std.mem.trimLeft(u8, trimmed_file_path, "/");
        }
        const output_path = try std.mem.concat(allocator, u8, &.{ trimmed_copy_to_path, "/", trimmed_file_path });
        defer allocator.free(output_path);

        // Files will not be in order, the path on system may not exist yet
        const last_slash = std.mem.lastIndexOfScalar(u8, output_path, '/');
        if (last_slash) |idx| {
            const parent_dir = output_path[0..idx];

            // Keep track of what was already create for this thread - perf
            if (path_map.get(parent_dir)) |_| {} else {
                if (!dry_run) {
                    try std.fs.cwd().makePath(parent_dir);
                }
                try path_map.put(parent_dir, true);
            }
        }

        // Skip if file already exists with the same size - perf
        const local_file_result = std.fs.cwd().openFile(output_path, .{ .mode = .read_only }) catch null;
        if (local_file_result) |local_file| {
            defer local_file.close();

            const file_stat = try local_file.stat();
            if (file_stat.size == file.size) {
                // std.debug.print("Skipping {s}\n", .{output_path});
                continue;
            }
        }

        stdout_mutex.lock();
        try stdout.print("[Thread:{d}] Copying {s}\n", .{ thread_id, output_path });
        stdout_mutex.unlock();

        if (dry_run) continue;

        //try stdout.print("Opening sftp handle\n", .{});
        const sftp_handle = c.libssh2_sftp_open_ex(
            sftp_session,
            file.path.ptr,
            @intCast(file.path.len),
            c.LIBSSH2_FXF_READ,
            0,
            c.LIBSSH2_SFTP_OPENFILE,
        ) orelse {
            continue;
        };
        defer _ = c.libssh2_sftp_close(sftp_handle);

        //try stdout.print("Creating local file to write to {s}\n", .{output_path});
        const local_file_try: std.fs.File.OpenError!std.fs.File = std.fs.cwd().createFile(output_path, .{});

        const local_file = local_file_try catch {
            continue;
        };

        defer local_file.close();

        //try stdout.print("Reading bytes\n", .{});
        var bytes_received: isize = 0;
        while (true) {
            bytes_received = c.libssh2_sftp_read(@constCast(sftp_handle), buffer.ptr, buffer_size);
            if (bytes_received == 0) break;
            if (bytes_received < 0) break;

            _ = try local_file.write(buffer[0..@intCast(bytes_received)]);
        }
    }

    _ = c.libssh2_session_disconnect(session, "Bye");
}

pub fn ssh2ExecuteCommand(
    allocator: std.mem.Allocator,
    session: *c.LIBSSH2_SESSION,
    command: []const u8,
) !std.ArrayList(u8) {
    const channel_type = "session";
    const channel = c.libssh2_channel_open_ex(
        session,
        channel_type,
        channel_type.len,
        c.LIBSSH2_CHANNEL_WINDOW_DEFAULT,
        c.LIBSSH2_CHANNEL_PACKET_DEFAULT,
        null,

        0,
    );

    if (channel == null) return error.ChannelOpenFailed;
    defer _ = c.libssh2_channel_free(channel);

    const exec_str = "exec";
    const exec_len = exec_str.len;

    if (c.libssh2_channel_process_startup(
        channel,
        exec_str,
        comptime exec_len,
        command.ptr,
        @intCast(command.len),
    ) != 0) {
        return error.CommandExecutionFailed;
    }

    var buffer: [1024 * 256]u8 = undefined;
    var result = std.ArrayList(u8).init(allocator);

    while (true) {
        const bytes_read = c.libssh2_channel_read(channel, &buffer, buffer.len);
        if (bytes_read > 0) {
            try result.appendSlice(buffer[0..@intCast(bytes_read)]);
        } else {
            break;
        }
    }

    _ = c.libssh2_channel_close(channel);
    _ = c.libssh2_channel_wait_closed(channel);

    return result;
}

pub fn listFilesRecursively(
    allocator: std.mem.Allocator,
    session: *c.LIBSSH2_SESSION,
    path: []const u8,
    output: *std.ArrayList(u8),
    files: *std.ArrayList(parser.FileInfo),
) !void {
    // var cmd_buffer: [4103]u8 = 4103 ** "";
    //
    //

    const bash_command =
        "if stat --format=\"\" . >/dev/null 2>&1; then\n" ++
        "    find {s} -exec stat --format=\"%A\\0%h\\0%U\\0%G\\0%s\\0%Y\\0%n\" {{}} +\n" ++
        "else\n" ++
        "    find {s} -exec stat -f \"%Sp\\0%l\\0%Su\\0%Sg\\0%z\\0%m\\0%N\" {{}} +\n" ++
        "fi";
    var cmd_buffer: [4103]u8 = [_]u8{0} ** 4103;
    // const command = try std.fmt.bufPrint(&cmd_buffer, "ls -la {s}", .{path});
    const command = try std.fmt.bufPrint(&cmd_buffer, bash_command, .{ path, path });

    output.* = try ssh2ExecuteCommand(allocator, session, command);
    // defer output.deinit();

    try parser.listing(allocator, output, files);
    // defer parser.listingDeinit(allocator, &files);

    // for (files.items) |*file| {
    //     if (std.mem.eql(u8, file.name, ".") or std.mem.eql(u8, file.name, "..")) continue;

    //     // const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ path, file.name });

    //     const permissions_copy = try allocator.dupe(u8, file.permissions);
    //     const owner_copy = try allocator.dupe(u8, file.owner);
    //     const group_copy = try allocator.dupe(u8, file.group);
    //     const name_copy = try allocator.dupe(u8, file.name);
    //     const timestamp_copy = try allocator.dupe(u8, file.timestamp);

    //     try file_list.append(.{
    //         .permissions = permissions_copy,
    //         .owner = owner_copy,
    //         .group = group_copy,
    //         .size = file.size,
    //         .timestamp = timestamp_copy,
    //         .name = name_copy,
    //         .is_dir = file.is_dir,
    //         .path = name_copy,
    //     });
    // }
}
