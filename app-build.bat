@echo on
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
rem Your build commands here

rmdir /s /q .zig-cache
zig build-exe src/main.zig ^
    -O Debug ^
    -target x86_64-windows-msvc ^
    -D_CRT_SECURE_NO_WARNINGS ^
    -D_AMD64_ ^
    -rcincludes=msvc ^
    -llibssh2 ^
    -ladvapi32 ^
    -lbcrypt ^
    -lcrypt32 ^
    -L ./libssh2_build/src ^
    -I ./libssh2/include ^
    -isystem "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.42.34433\include" ^
    -isystem "C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\ucrt" ^
    -isystem "C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\um" ^
    -isystem "C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\shared"
    

rmdir /s /q .zig-cache
zig build-exe src/main.zig ^
    -O ReleaseSmall ^
    -target x86_64-windows-msvc ^
    -D_CRT_SECURE_NO_WARNINGS ^
    -D_AMD64_ ^
    -rcincludes=msvc ^
    -llibssh2 ^
    -ladvapi32 ^
    -lbcrypt ^
    -lcrypt32 ^
    -L ./libssh2_build/src ^
    -I ./libssh2/include ^
    -isystem "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.42.34433\include" ^
    -isystem "C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\ucrt" ^
    -isystem "C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\um" ^
    -isystem "C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\shared"
