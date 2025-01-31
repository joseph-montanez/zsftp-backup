@echo off
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"

rmdir /s /q libssh2_build_debug
mkdir libssh2_build_debug
cd libssh2_build_debug
cmake -G "Ninja" -DCMAKE_BUILD_TYPE=Debug ^
    -DCMAKE_C_COMPILER="cl" ^
    -DCRYPTO_BACKEND="WinCNG" ^
    -DCMAKE_C_FLAGS="/wd4200" ^
    ../libssh2
cmake --build .
cd ..

rmdir /s /q libssh2_build_release
mkdir libssh2_build_release
cd libssh2_build_release
cmake -G "Ninja" -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_C_COMPILER="cl" ^
    -DCRYPTO_BACKEND="WinCNG" ^
    -DCMAKE_C_FLAGS="/wd4200" ^
    ../libssh2
cmake --build .
cd ..


