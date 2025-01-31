@echo off
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" arm64
set "PATH=%VSINSTALLDIR%\VC\Tools\Llvm\bin;%PATH%"
set "CL=/D_ARM64_ /D_ARM_WINAPI_PARTITION_DESKTOP_SDK_AVAILABLE_ /D_WIN32_WINNT=0x0A00 /DNTDDI_VERSION=0x0A000000"
set "CMAKE_GENERATOR=Ninja"
cd /d %~dp0

rmdir /s /q libssh2_build_debug_arm64
mkdir libssh2_build_debug_arm64
cd libssh2_build_debug_arm64
cmake -G "Ninja" -DCMAKE_BUILD_TYPE=Debug ^
    -DCMAKE_C_COMPILER="cl" ^
    -DCRYPTO_BACKEND="WinCNG" ^
    -DCMAKE_C_FLAGS="/wd4200" ^
    ../libssh2
cmake --build .
cd ..

rmdir /s /q libssh2_build_release_arm64
mkdir libssh2_build_release_arm64
cd libssh2_build_release_arm64
cmake -G "Ninja" -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_C_COMPILER="cl" ^
    -DCRYPTO_BACKEND="WinCNG" ^
    -DCMAKE_C_FLAGS="/wd4200" ^
    ../libssh2
cmake --build .
cd ..


