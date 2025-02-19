# ZSFTP Backup

Zig **0.14.0** based sftp backup, a statically linked binary, so only the executable is needed, you can even embed your certificates into the executable. This also allows you to create custom builds with embedded server information including certificates and password. This leverages `libssh2` and `mbedtls` for macOS/Linux and only `libssh2` with Windows 10/11 encrpytion. For Windows, libssh2 is already built for **x64** and **arm64**, so you do not need to compile that library, just run `zig build` with the latest version of Visual Studio 2022 also installed.

## Command Parameters

| Option        | Description |
|--------------|------------|
| **`--host`** | IP address (127.0.0.1) or domain name (google.com) |
| **`--username`** | Username of the SFTP account |
| **`--password`** | Password for the SFTP account |
| **`--public_key`** | The public key, currently EDC25519 is not supported, use RSA. Due to libssh2, __*both public and private keys are needed*__. |
| **`--private_key`** | The private key, currently EDC25519 is not supported, use RSA. Due to libssh2, __*both public and private keys are needed*__. |
| **`--copy_from`** | Remote path on the server to copy from |
| **`--copy_to`** | Local path to copy the files to |


**Example**

`zig-out/bin/zsftp-sync-macOS-aarch64-Debug --port 2222 --ip 127.0.0.1 --username testuser --password testpass --copy_to=docker_test`

## Embedded Authorization Information Into Runtime.

One of the features I needed was to allow the process to run without wrapping `rsync` around an Expect shell script or using `ssh-pass`. While certificates are always a better option, other things like host verfication might block the request. This side steps all of this and allows you to just embed everything to authorize from the binary itself.

The example that showed how you use the binary as-is without embedding, you can then use the same parameters at build to embed, but the syntax is different.

```zig
# Username / Password Example
zig build -Dport="2222" -Dhost="127.0.0.1" -Dusername="testuser" -Dpassword="testpass" -Dcopy_to="docker_test"


# Certificate Example
zig build -Dport="2222" -Dhost="127.0.0.1" -Dusername="testuser" -Dpublic_key="id_rsa_libssh2.pub" -Dprivate_key="id_rsa_libssh2" -Dcopy_to="docker_test"
```

Then when you run `zig-out/bin/zsftp-sync-macOS-aarch64-Debug` it will use the pass authorization information pass into at build time. You can still override things so maybe your certicate has changed but don't want a full rebuild.

## Build Parameters

```zig
const windows_sdk_path = b.option([]const u8, "windows_sdk_path", "Path to Windows SDK") orelse "C:\\Program Files (x86)\\Windows Kits\\10";
const visual_studio_path = b.option([]const u8, "visual_studio_path", "Path to Visual Studio") orelse "C:\\Program Files\\Microsoft Visual Studio\\2022\\Community\\VC\\Tools\\MSVC\\14.42.34433";
const windows_sdk_version = b.option([]const u8, "windows_sdk_version", "Version Of Windows SDK") orelse "10.0.26100.0";
```

| Option        | Description |
|--------------|------------|
| **`-Dwindows_sdk_path`** | Path to Windows Kit (defaults to C:\Program Files (x86)\Windows Kits\10) |
| **`-Dvisual_studio_path`** | Path to Visual Studio (defaults to C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.42.34433) |
| **`-Dwindows_sdk_version`** | Windows Kit version (defaults to 10.0.26100.0), you can use any version you have on your system 10.0.26100 is not required.|
| **`-Dhost`** | IP address (127.0.0.1) or domain name (google.com) |
| **`-Dusername`** | Username of the SFTP account |
| **`-Dpassword`** | Password for the SFTP account |
| **`-Dpublic_key`** | The public key, currently EDC25519 is not supported, use RSA. Due to libssh2, __*both public and private keys are needed*__. |
| **`-Dprivate_key`** | The private key, currently EDC25519 is not supported, use RSA. Due to libssh2, __*both public and private keys are needed*__. |
| **`-Dcopy_from`** | Remote path on the server to copy from |
| **`-Dcopy_to`** | Local path to copy the files to |


## Building on macOS/Linux

Right now I do not have an all in one solution for libssh2, you can run the following:

```bash
git submodule update --init --recursive
make macos-debug # or make linux
```

## Building on Windows

You need to have Visual Studio 2022 installed

### Windows 11 Build Instructions

```bash
    git clone https://github.com/libssh2/libssh2.git libssh2
    zig build -Dtarget=x86_64-windows-msvc
```

## Cross Compiling To Windows

Zig allows cross compiling to Windows however since I have everything setup to use Windows encryption the MSVC C ABI must be targeted. Clang (`zig cc`), does not support using the GNU C ABI while linking to Windows libs, so you must have the Windows libs and Visual Studio C headers on your local system. make sure you download the x64/arm64 or which ever architech you are going to support. Maybe in the furture I will just dynamically load the DLLs, to allow using the GNU C ABI and thus bypassing needing to download Visual Studio 2022.

**Folders to copy to your local Linux/macOS system from Windows**

> Windows 10 SDK - `C:\Program Files (x86)\Windows Kits\10`

> Visual Studio Compiler Headers - `C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.42.34433`

I do not have cross compiling of `libssh2` right now. However I am including the static libraries for `libssh2` for Windows that you can use, so you do not need to compile libssh2 on Windows.

**ARM64/AARCH64**
```
libssh2-arm64-debug.lib
libssh2-arm64-release.lib
```

**x64/x86_64**
```
libssh2-x64-debug.lib
libssh2-x64-release.lib
```

These are linked automatically, so you don't need to do anything for libssh2 on Windows.

**Here is an example of compiling for Windows 10/11 from macOS**

```bash
# Windows x64
zig build -Dtarget=x86_64-windows-msvc \
          -Dwindows_sdk_path="/Users/josephmontanez_1/Downloads/win10kit" \
          -Dvisual_studio_path="/Users/josephmontanez_1/Downloads/vs14/14.42.34433" \
          -Dwindows_sdk_version="10.0.26100.0" \
          -Doptimize=Debug

# Windows Arm64
zig build -Dtarget=aarch64-windows-msvc \
          -Dwindows_sdk_path="/Users/josephmontanez_1/Downloads/win10kit" \
          -Dvisual_studio_path="/Users/josephmontanez_1/Downloads/vs14/14.42.34433" \
          -Dwindows_sdk_version="10.0.26100.0" \
          -Doptimize=Debug

```

## Rebuilding LibSSH2 on Windows

If you really need **ECD25519** support for certificates you need to compile libssh2 with openssl as an encryption backend, rather than rely on Windows 10 built-in encryption. Please look at `libssh2-build.bat` and `libssh2-build-arm64.bat` for how to swap the encryption backend.

