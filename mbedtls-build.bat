@echo off
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
rem Your build commands here

rmdir /s /q mbedtls_build
mkdir mbedtls_build
cd mbedtls_build
cmake -G "Ninja" -DCMAKE_BUILD_TYPE=Debug ^
    -DCMAKE_C_COMPILER="cl" ^
    -DUSE_STATIC_MBEDTLS_LIBRARY=ON ^
    -DUSE_SHARED_MBEDTLS_LIBRARY=OFF ^
    -DBUILD_SHARED_LIBS=OFF ^
    -DMBEDTLS_CONFIG_FILE="C:/projects/zsftp-sync/mbedtls/include/mbedtls/mbedtls_config.h" ^
    -DMSVC_STATIC_RUNTIME=ON ^
     ../mbedtls
cmake --build .
