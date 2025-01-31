const std = @import("std");
const builtin = @import("builtin");
const parser = @import("parser/Commands.zig");
const sftp = @import("sftp.zig");
const c = @cImport({
    if (builtin.os.tag == .windows) {
        // Cannot import windows.h, cause other issues
        @cDefine("MIDL_INTERFACE", "struct");
    }
    @cInclude("libssh2.h");
    @cInclude("libssh2_sftp.h");
});
const config = @cImport({
    @cInclude("config.h");
});

const native_os = builtin.os.tag;

const ParamType = enum {
    is_string,
    is_bool,
    is_int,
};

const ParamValue = union {
    int: u16,
    string: []const u8,
    boolean: bool,
};

const Param = struct {
    typeof: ParamType,
    default: ParamValue,
    value: ParamValue,
    required: bool,
    help: []const u8,
    alloc: bool,
};

const Params = struct {
    host: Param,
    port: Param,
    username: Param,
    password: Param,
    copy_from: Param,
    copy_to: Param,
    private_key: Param,
    public_key: Param,
    dry_run: Param,

    pub fn init(allocator: std.mem.Allocator) !*Params {
        const host: []const u8 = if (@hasDecl(config, "HOST")) config.HOST else "localhost";
        const port: u16 = if (@hasDecl(config, "PORT")) config.PORT else 22;
        const username: []const u8 = if (@hasDecl(config, "USERNAME")) config.USERNAME else "";
        const password: []const u8 = if (@hasDecl(config, "PASSWORD")) config.PASSWORD else "";
        const copy_to: []const u8 = if (@hasDecl(config, "COPY_TO")) config.COPY_TO else "";
        const copy_from: []const u8 = if (@hasDecl(config, "COPY_FROM")) config.COPY_FROM else "";
        const private_key: []const u8 = if (@hasDecl(config, "PRIVATE_KEY")) config.PRIVATE_KEY else "";
        const public_key: []const u8 = if (@hasDecl(config, "PUBLIC_KEY")) config.PUBLIC_KEY else "";
        const dry_run: bool = if (@hasDecl(config, "DRY_RUN")) config.DRY_RUN else false;

        const params = try allocator.create(Params);
        params.* = Params{
            .host = Param{
                .typeof = ParamType.is_string,
                .default = .{ .string = host },
                .value = .{ .string = host },
                .required = true,
                .help = "Domain name or IP4/IP6 address",
                .alloc = false,
            },
            .port = Param{
                .typeof = ParamType.is_int,
                .default = .{ .int = port },
                .value = .{ .int = port },
                .required = false,
                .help = "Number defaults to port 22",
                .alloc = false,
            },
            .username = Param{
                .typeof = ParamType.is_string,
                .default = .{ .string = username },
                .value = .{ .string = username },
                .required = false,
                .help = "Specify the username",
                .alloc = false,
            },
            .password = Param{
                .typeof = ParamType.is_string,
                .default = .{ .string = password },
                .value = .{ .string = password },
                .required = false,
                .help = "Specify the password",
                .alloc = false,
            },
            .copy_from = Param{
                .typeof = ParamType.is_string,
                .default = .{ .string = copy_from },
                .value = .{ .string = copy_from },
                .required = false,
                .help = "Specify the source path",
                .alloc = false,
            },
            .copy_to = Param{
                .typeof = ParamType.is_string,
                .default = .{ .string = copy_to },
                .value = .{ .string = copy_to },
                .required = false,
                .help = "Specify the destination path",
                .alloc = false,
            },
            .private_key = Param{
                .typeof = ParamType.is_string,
                .default = .{ .string = private_key },
                .value = .{ .string = private_key },
                .required = false,
                .help = "Specify the private key file",
                .alloc = false,
            },
            .public_key = Param{
                .typeof = ParamType.is_string,
                .default = .{ .string = public_key },
                .value = .{ .string = public_key },
                .required = false,
                .help = "Specify the public key file",
                .alloc = false,
            },
            .dry_run = Param{
                .typeof = ParamType.is_bool,
                .default = .{ .boolean = dry_run },
                .value = .{ .boolean = dry_run },
                .required = false,
                .help = "Perform a dry run without making changes",
                .alloc = false,
            },
        };
        return params;
    }

    pub fn deinit(self: *Params, allocator: std.mem.Allocator) void {
        if (self.host.alloc) {
            allocator.free(self.host.value.string);
        }
        if (self.username.alloc) {
            allocator.free(self.username.value.string);
        }
        if (self.password.alloc) {
            allocator.free(self.password.value.string);
        }
        if (self.copy_from.alloc) {
            allocator.free(self.copy_from.value.string);
        }
        if (self.copy_to.alloc) {
            allocator.free(self.copy_to.value.string);
        }
        if (self.private_key.alloc) {
            allocator.free(self.private_key.value.string);
        }
        if (self.public_key.alloc) {
            allocator.free(self.public_key.value.string);
        }
        allocator.destroy(self);
    }
};

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa_allocator = gpa.allocator();
    defer {
        if (gpa.deinit() == .leak) {
            @panic("We got a leak buddy!");
        }
    }

    // var arena = std.heap.ArenaAllocator.init(gpa_allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();

    const allocator = gpa_allocator;

    const stdout = std.io.getStdOut().writer();

    try stdout.print("Getting ready to read the process parameters\n", .{});

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    var params = try Params.init(gpa_allocator);
    defer params.deinit(gpa_allocator);

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            try stdout.print("Usage: zsftp_sync [OPTIONS]\n", .{});
            inline for (@typeInfo(Params).@"struct".fields) |param| {
                const opt = @field(params, param.name);
                try stdout.print("--{s}  {s}\n", .{ param.name, opt.help });
            }
            return;
        }

        inline for (@typeInfo(Params).@"struct".fields) |param| {
            const arg_name = std.mem.trimLeft(u8, arg, "-");

            if (std.mem.eql(u8, arg_name, param.name)) {
                switch (@field(params, param.name).typeof) {
                    ParamType.is_int => {
                        const value = args.next() orelse return error.MissingValue;
                        @field(params, param.name).value = .{ .int = try std.fmt.parseInt(u16, value, 10) };
                        @field(params, param.name).alloc = true;
                    },
                    ParamType.is_bool => {
                        @field(params, param.name).value = .{ .boolean = true };
                    },
                    ParamType.is_string => {
                        const value = args.next() orelse return error.MissingValue;

                        std.debug.print("\t{s} - {s}\n", .{ param.name, value });
                        @field(params, param.name).value = .{ .string = try gpa_allocator.dupe(u8, value) };
                        @field(params, param.name).alloc = true;
                    },
                }
            }
        }
    }

    if (std.mem.eql(u8, params.host.value.string, "")) {
        try stdout.print("Error: Missing required arguments.\n", .{});
        try stdout.print("Usage: --host <DOMAIN OR IP>\n", .{});
        return error.IpMissing;
    }

    const host = params.host.value.string;
    const port = params.port.value.int;
    const username = params.username.value.string;
    const password = params.password.value.string;
    const private_key = params.private_key.value.string;
    const public_key = params.public_key.value.string;
    const copy_to = params.copy_to.value.string;
    const copy_from = params.copy_from.value.string;
    const dry_run = params.dry_run.value.boolean;

    var sock_fd: std.posix.socket_t = undefined;
    defer {
        if (native_os == .windows) {
            _ = std.posix.close(sock_fd);
        } else if (sock_fd != -1) {
            _ = std.posix.close(sock_fd);
        }
    }

    var address_list: *std.net.AddressList = try std.net.getAddressList(allocator, host, port);
    defer address_list.deinit();

    const server_addr: std.net.Address = address_list.addrs[0];

    // Initialize libssh2
    if (c.libssh2_init(0) != 0) {
        std.debug.print("Failed to initialize libssh2\n", .{});
        return error.InitializationFailed;
    }
    defer c.libssh2_exit();

    // Create a socket and connect
    sock_fd = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0);
    const stream: std.net.Stream = try std.net.tcpConnectToAddress(server_addr);

    // Create a session
    const session: ?*c.LIBSSH2_SESSION = c.libssh2_session_init_ex(null, null, null, null);
    if (session == null) {
        std.debug.print("Failed to initialize SSH session\n", .{});
        return error.SessionInitFailed;
    }
    defer _ = c.libssh2_session_free(session);

    // Enable tracing
    // _ = c.libssh2_trace(session, c.LIBSSH2_TRACE_CONN | c.LIBSSH2_TRACE_TRANS);

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
        std.debug.print("SSH session handshake failed ({}): {s}\n", .{ err_code, err_msg });
        return error.HandshakeFailed;
    }

    if (private_key.len > 0) {
        var is_embedded = false;
        if (std.mem.indexOf(u8, private_key, "embed://")) |is_embed| {
            is_embedded = is_embed >= 0;
        }

        if (!is_embedded and !sftp.fileExistsAndReadable(private_key)) {
            std.debug.print("Error: Private key file {s} is not readable or does not exist\n", .{private_key});
            return error.FileNotFound;
        }
    }

    if (public_key.len > 0) {
        var is_embedded = false;
        if (std.mem.indexOf(u8, public_key, "embed://")) |is_embed| {
            is_embedded = is_embed >= 0;
        }

        if (!is_embedded and !sftp.fileExistsAndReadable(public_key)) {
            std.debug.print("Public key file {s} is not readable or does not exist\n", .{public_key});
            return error.FileNotFound;
        }
    }

    const is_auth = try sftp.authorize(session.?, username, password, private_key, public_key);

    if (is_auth != 0) {
        try stdout.print("Authentication failed\n", .{});
        return error.AuthenticationFailed;
    }

    std.debug.print("Authentication successful! Grabbing from {s}\n", .{copy_from});

    var file_list = std.ArrayList(parser.FileInfo).init(allocator);
    defer file_list.deinit();

    if (session) |sessionRaw| {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();

        try sftp.listFilesRecursively(allocator, sessionRaw, copy_from, &output, &file_list);
        try stdout.print("Total Files: {d}\n", .{file_list.items.len});

        const num_threads = 4; // Number of parallel downloads

        var queue = std.ArrayList(parser.FileInfo).init(allocator);
        defer queue.deinit();

        var lock = std.Thread.Mutex{};
        var cond = std.Thread.Condition{};
        var done = std.atomic.Value(bool).init(false);

        var context = sftp.WorkerContext{
            .queue = &queue,
            .lock = &lock,
            .cond = &cond,
            .done = &done,
        };

        var threads: [num_threads]std.Thread = undefined;

        for (0..num_threads) |i| {
            threads[i] = try std.Thread.spawn(.{}, sftp.downloadFilesQueue, .{
                &context, server_addr, username, password, public_key, private_key, copy_to, dry_run,
            });
        }

        for (file_list.items) |file| {
            lock.lock();
            queue.append(file) catch {};
            cond.signal();
            lock.unlock();
        }

        lock.lock();
        done.store(true, .release);
        cond.broadcast();
        lock.unlock();

        for (threads) |t| {
            t.join();
        }
    }

    // Clean up
    _ = c.libssh2_session_disconnect(session, "Bye");
}
