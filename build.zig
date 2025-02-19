const std = @import("std");
const builtin = @import("builtin");

fn readFileContents(b: *std.Build, path: []const u8) []const u8 {
    var file = std.fs.cwd().openFile(path, .{}) catch |err| {
        std.debug.print("Failed to open file: {s}\n", .{@errorName(err)});
        return "";
    };
    defer file.close();

    const allocator = b.allocator;
    const contents = file.readToEndAlloc(allocator, std.math.maxInt(usize)) catch |err| {
        std.debug.print("Failed to read file: {s}\n", .{@errorName(err)});
        return "";
    };

    return contents;
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const windows_sdk_path = b.option([]const u8, "windows_sdk_path", "Path to Windows SDK") orelse "C:\\Program Files (x86)\\Windows Kits\\10";
    const visual_studio_path = b.option([]const u8, "visual_studio_path", "Path to Visual Studio") orelse "C:\\Program Files\\Microsoft Visual Studio\\2022\\Community\\VC\\Tools\\MSVC\\14.43.34808";
    const windows_sdk_version = b.option([]const u8, "windows_sdk_version", "Version Of Windows SDK") orelse "10.0.26100.0";

    const host = b.option([]const u8, "host", "Domain or IP of the server") orelse null;
    const port = b.option([]const u8, "port", "SFTP port of the server") orelse "22";
    const username = b.option([]const u8, "username", "Username for SSH auth") orelse null;
    const password = b.option([]const u8, "password", "Password for SSH auth") orelse null;
    const private_key = b.option([]const u8, "private_key", "Path to the private key file") orelse null;
    const public_key = b.option([]const u8, "public_key", "Path to the public key file") orelse null;
    const copy_from = b.option([]const u8, "copy_from", "File path on remote server to copy from");
    const copy_to = b.option([]const u8, "copy_to", "File path on the local disk to copy to");

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = blk: {
        var tgt = b.standardTargetOptions(.{});
        if (tgt.result.os.tag == .windows) {
            tgt.result.abi = .msvc; // Force MSVC ABI only on Windows
        }
        break :blk tgt;
    };

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "zsftp-sync",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    const string_module = b.createModule(.{
        .root_source_file = .{
            .cwd_relative = "src/string/String.zig",
        },
    });

    const build_mode = switch (optimize) {
        .Debug => "Debug",
        else => "Release",
    };

    const arch = switch (target.result.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "aarch64",
        else => @panic("Unsupported architecture"),
    };

    const win_arch = switch (target.result.cpu.arch) {
        .x86_64 => "x64",
        .aarch64 => "arm64",
        else => @panic("Unsupported architecture"),
    };

    const exe_name: []const u8 = blk: {
        break :blk switch (target.result.os.tag) {
            .macos => std.fmt.allocPrint(b.allocator, "zsftp-sync-macOS-{s}-{s}", .{ arch, build_mode }) catch "",
            .windows => std.fmt.allocPrint(b.allocator, "zsftp-sync-Windows-{s}-{s}", .{ arch, build_mode }) catch "",
            .linux => std.fmt.allocPrint(b.allocator, "zsftp-sync-Linux-{s}-{s}", .{ arch, build_mode }) catch "",
            else => @panic("unsupported"),
        };
    };

    const exe = b.addExecutable(.{
        .name = exe_name,
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const private_key_content = if (private_key) |key|
        std.mem.concat(b.allocator, u8, &[_][]const u8{ "embed://", readFileContents(b, key) }) catch ""
    else
        "";

    const public_key_content = if (public_key) |key|
        std.mem.concat(b.allocator, u8, &[_][]const u8{ "embed://", readFileContents(b, key) }) catch ""
    else
        "";

    const config: *std.Build.Step.ConfigHeader = b.addConfigHeader(.{
        .include_path = "config.h",
    }, .{
        .HOST = host,
        .PORT = std.fmt.parseInt(u16, port, 10) catch 22,
        .USERNAME = username,
        .PASSWORD = password,
        .PRIVATE_KEY = private_key_content,
        .PUBLIC_KEY = public_key_content,
        .COPY_FROM = copy_from,
        .COPY_TO = copy_to,
    });

    exe.addConfigHeader(config);

    exe.addIncludePath(.{ .cwd_relative = "libssh2/include" });

    if (target.result.os.tag == .windows) {
        exe.addLibraryPath(.{ .cwd_relative = "" });

        const libssh2_lib = if (target.result.cpu.arch == .x86_64) switch (optimize) {
            .Debug => "libssh2-x64-debug",
            else => "libssh2-x64-release",
        } else switch (optimize) {
            .Debug => "libssh2-arm64-debug",
            else => "libssh2-arm64-release",
        };

        const win_include_shared = std.fmt.allocPrint(b.allocator, "{s}/Include/{s}/shared", .{ windows_sdk_path, windows_sdk_version }) catch "";
        const win_include_um = std.fmt.allocPrint(b.allocator, "{s}/Include/{s}/um", .{ windows_sdk_path, windows_sdk_version }) catch "";
        const win_include_ucrt = std.fmt.allocPrint(b.allocator, "{s}/Include/{s}/ucrt", .{ windows_sdk_path, windows_sdk_version }) catch "";

        std.debug.print("Windows Include Path: {s}\n", .{win_include_shared});
        std.debug.print("Windows Include Path: {s}\n", .{win_include_um});
        std.debug.print("Windows Include Path: {s}\n", .{win_include_ucrt});

        exe.addIncludePath(.{ .cwd_relative = win_include_shared });
        exe.addIncludePath(.{ .cwd_relative = win_include_um });
        exe.addIncludePath(.{ .cwd_relative = win_include_ucrt });

        const win_lib_um = std.fmt.allocPrint(b.allocator, "{s}/Lib/{s}/um/{s}", .{ windows_sdk_path, windows_sdk_version, win_arch }) catch "";
        const win_lib_ucrt = std.fmt.allocPrint(b.allocator, "{s}/Lib/{s}/ucrt/{s}", .{ windows_sdk_path, windows_sdk_version, win_arch }) catch "";

        exe.addLibraryPath(.{ .cwd_relative = win_lib_um });
        exe.addLibraryPath(.{ .cwd_relative = win_lib_ucrt });

        std.debug.print("Windows Library Path: {s}\n", .{win_lib_ucrt});
        std.debug.print("Windows Library Path: {s}\n", .{win_lib_um});

        // MSVC Compiler
        const msvc_include = std.fmt.allocPrint(b.allocator, "{s}/include", .{visual_studio_path}) catch "";
        const msvc_lib = std.fmt.allocPrint(b.allocator, "{s}/lib/{s}", .{ visual_studio_path, win_arch }) catch "";

        std.debug.print("Visual Studio Include Path: {s}\n", .{msvc_include});
        std.debug.print("Visual Studio Library Path: {s}\n", .{msvc_lib});

        exe.addSystemIncludePath(.{ .cwd_relative = msvc_include });
        exe.addLibraryPath(.{ .cwd_relative = msvc_lib });

        // Windows 10 SDK
        const win_ucrt = std.fmt.allocPrint(b.allocator, "{s}/ucrt", .{windows_sdk_path}) catch "";
        const win_um = std.fmt.allocPrint(b.allocator, "{s}/um", .{windows_sdk_path}) catch "";
        const win_shared = std.fmt.allocPrint(b.allocator, "{s}/shared", .{windows_sdk_path}) catch "";
        exe.addSystemIncludePath(.{ .cwd_relative = win_ucrt });
        exe.addSystemIncludePath(.{ .cwd_relative = win_um });
        exe.addSystemIncludePath(.{ .cwd_relative = win_shared });

        const win_redist_ucrt = std.fmt.allocPrint(b.allocator, "{s}/bin/{s}/{s}/ucrt", .{ windows_sdk_path, windows_sdk_version, win_arch }) catch "";
        exe.addLibraryPath(.{ .cwd_relative = win_redist_ucrt });

        exe.linkSystemLibrary("crypt32");
        exe.linkSystemLibrary("bcrypt");
        exe.linkSystemLibrary("advapi32");

        exe.linkSystemLibrary2(libssh2_lib, .{ .preferred_link_mode = .static, .use_pkg_config = .no, .search_strategy = .no_fallback });

        if (optimize == .Debug) {
            exe.linkSystemLibrary("vcruntimed");
            exe.linkSystemLibrary("ucrtd");
            exe.linkSystemLibrary("libcmt");

            // Setup LibSSH2 debugging PDB file
            var install_file: []const u8 = undefined;
            if (target.result.cpu.arch == .aarch64) {
                install_file = "libssh2-arm64-debug.pdb";
            } else if (target.result.cpu.arch == .x86_64) {
                install_file = "libssh2-x64-debug.pdb";
            }
            const install = b.getInstallStep();
            const install_data = b.addInstallFile(
                .{ .cwd_relative = install_file },
                "bin/libssh2_static.pdb",
            );
            install.dependOn(&install_data.step);
        } else {
            if (target.result.cpu.arch == .x86_64) {
                // Arm has no msvcrt
                exe.linkSystemLibrary("msvcrt"); // Microsoft C Runtime
            }
            exe.linkSystemLibrary("ucrt"); // Universal C Runtime
            exe.linkSystemLibrary("vcruntime"); // Visual C Runtime
        }

        // Cannot link LibC when targeting msvc c abi
        //exe.linkLibC();
    } else {
        const os_name = if (target.result.os.tag == .macos) "macos" else "linux";

        const libssh2_path = std.fmt.allocPrint(b.allocator, "build/libssh2-{s}-{s}-{s}/src", .{ arch, os_name, build_mode }) catch "";
        const mbedtls_path = std.fmt.allocPrint(b.allocator, "build/mbedtls-{s}-{s}-{s}/library", .{ arch, os_name, build_mode }) catch "";
        const thirdparty_p256m = std.fmt.allocPrint(b.allocator, "build/mbedtls-{s}-{s}-{s}/3rdparty/p256-m", .{ arch, os_name, build_mode }) catch "";
        const thirdparty_everest = std.fmt.allocPrint(b.allocator, "build/mbedtls-{s}-{s}-{s}/3rdparty/everest", .{ arch, os_name, build_mode }) catch "";

        exe.addLibraryPath(.{ .cwd_relative = libssh2_path });
        exe.addLibraryPath(.{ .cwd_relative = mbedtls_path });
        exe.addLibraryPath(.{ .cwd_relative = thirdparty_p256m });
        exe.addLibraryPath(.{ .cwd_relative = thirdparty_everest });
        exe.linkSystemLibrary("ssh2");
        exe.linkSystemLibrary("mbedcrypto");
        exe.linkSystemLibrary("mbedx509");
        exe.linkSystemLibrary("mbedtls");
    }

    // exe.addModule("string", string_module);
    exe.root_module.addImport("string", string_module);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const cmd_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/parser/Commands.zig"),
        .target = target,
        .optimize = optimize,
    });
    cmd_unit_tests.root_module.addImport("string", string_module);

    const run_cmd_unit_tests = b.addRunArtifact(cmd_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
    test_step.dependOn(&run_cmd_unit_tests.step);
}
