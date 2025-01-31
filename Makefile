# Compiler
ZIG=zig
CC=$(ZIG) cc
CMAKE=cmake

# Detect macOS Architecture
OS_ARCH=$(shell uname -m)
MACOS_TARGET=$(if $(filter arm64,$(OS_ARCH)),aarch64-macos,x86_64-macos)

# Target Platforms
TARGET_MACOS=$(MACOS_TARGET)
TARGET_LINUX=x86_64-linux-gnu
TARGET_LINUX_ARM=aarch64-linux-gnu
TARGET_WIN=x86_64-windows-gnu
TARGET_WIN_ARM=aarch64-windows-gnu

# Directories
BUILD_DIR=./build
MBEDTLS_SRC=mbedtls
LIBSSH2_SRC=libssh2

# Output Binaries
APP_DEBUG=app_debug
APP_RELEASE=app_release
SRC_DIR=src
SRC_FILES=$(wildcard $(SRC_DIR)/*.zig)
OUTPUT_FILE=$(BUILD_DIR)/$(APP_DEBUG)

# Zig Source
ZIG_SRC=src/main.zig

.PHONY: all clean macos debug release cross

all: release

clean:
	rm -rf $(BUILD_DIR)

# Build mbedtls for a specific target and build type
define build_mbedtls
	mkdir -p "$(BUILD_DIR)/mbedtls-$(1)-$(2)"
	cd "$(BUILD_DIR)/mbedtls-$(1)-$(2)" && CC="$(ZIG) cc" CXX="$(ZIG) c++" $(CMAKE) \
	    -DCMAKE_BUILD_TYPE=$(2) \
	    -DCMAKE_SYSTEM_NAME=Darwin \
	    -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
	    -DMBEDTLS_CONFIG_FILE='../../$(MBEDTLS_SRC)/include/mbedtls/mbedtls_config.h' \
	    $(abspath ./$(MBEDTLS_SRC))
	$(CMAKE) --build "$(BUILD_DIR)/mbedtls-$(1)-$(2)"
endef

# Build libssh2 for a specific target and build type
define build_libssh2
	mkdir -p "$(BUILD_DIR)/libssh2-$(1)-$(2)"
	cd "$(BUILD_DIR)/libssh2-$(1)-$(2)" && CC="$(ZIG) cc" CXX="$(ZIG) c++" $(CMAKE) \
	    -DCMAKE_BUILD_TYPE=$(2) \
	    -DCMAKE_SYSTEM_NAME=Darwin \
	    -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
	    -DCRYPTO_BACKEND=mbedTLS \
	    -DLIBSSH2_ED25519=ON \
	    -DMBEDTLS_INCLUDE_DIRS=$(abspath $(MBEDTLS_SRC)/include) \
	    -DINCLUDE_DIRS=$(abspath $(MBEDTLS_SRC)/include) \
	    -DMBEDTLS_LIBRARIES="$(abspath $(BUILD_DIR)/mbedtls-$(1)-$(2)/library/libmbedtls.a);$(abspath $(BUILD_DIR)/mbedtls-$(1)-$(2)/library/libmbedcrypto.a);$(abspath $(BUILD_DIR)/mbedtls-$(1)-$(2)/library/libmbedx509.a);$(abspath $(BUILD_DIR)/mbedtls-$(1)-$(2)/3rdparty/everest/libeverest.a)" \
	    $(abspath ./$(LIBSSH2_SRC))
	$(CMAKE) --build "$(BUILD_DIR)/libssh2-$(1)-$(2)"
endef

# Build Zig application for a specific target and build type
define build_app
	$(ZIG) build \
	    -Doptimize=$(2) \
	    -Dtarget=$(1)
endef

$(OUTPUT_FILE): $(SRC_FILES)
	$(call build_app,$(TARGET_MACOS),Debug,Debug,$(APP_DEBUG))

build: $(OUTPUT_FILE)

# Build Debug and Release versions for macOS	
macos-release:
	$(call build_mbedtls,$(TARGET_MACOS),Release)
	$(call build_libssh2,$(TARGET_MACOS),Release)
	$(call build_app,$(TARGET_MACOS),ReleaseSmall,Release,$(APP_RELEASE))

macos-debug:
	$(call build_mbedtls,$(TARGET_MACOS),Debug)
	$(call build_libssh2,$(TARGET_MACOS),Debug)
	$(call build_app,$(TARGET_MACOS),Debug,Debug,$(APP_DEBUG))

# Build Debug and Release versions for Linux (x86_64)
linux:
	$(call build_mbedtls,$(TARGET_LINUX),Debug)
	$(call build_mbedtls,$(TARGET_LINUX),Release)
	$(call build_libssh2,$(TARGET_LINUX),Debug)
	$(call build_libssh2,$(TARGET_LINUX),Release)
	$(call build_app,$(TARGET_LINUX),Debug,Debug,$(APP_DEBUG))
	$(call build_app,$(TARGET_LINUX),ReleaseSmall,Release,$(APP_RELEASE))

# Build Debug and Release versions for Windows (x86_64)
windows-release:
	$(call build_mbedtls,$(TARGET_WIN),Release)
	$(call build_libssh2,$(TARGET_WIN),Release)
	$(call build_app,$(TARGET_WIN),ReleaseSmall,Release,$(APP_RELEASE))

windows-debug:
	$(call build_mbedtls,$(TARGET_WIN),Debug)
	$(call build_libssh2,$(TARGET_WIN),Debug)
	$(call build_app,$(TARGET_WIN),Debug,Debug,$(APP_DEBUG))

# Build Debug and Release versions for ARM Linux
linux-arm:
	$(call build_mbedtls,$(TARGET_LINUX_ARM),Debug)
	$(call build_mbedtls,$(TARGET_LINUX_ARM),Release)
	$(call build_libssh2,$(TARGET_LINUX_ARM),Debug)
	$(call build_libssh2,$(TARGET_LINUX_ARM),Release)
	$(call build_app,$(TARGET_LINUX_ARM),Debug,Debug,$(APP_DEBUG))
	$(call build_app,$(TARGET_LINUX_ARM),ReleaseSmall,Release,$(APP_RELEASE))

# Build Debug and Release versions for ARM Windows
windows-arm-release:
	$(call build_mbedtls,$(TARGET_WIN_ARM),Release)
	$(call build_libssh2,$(TARGET_WIN_ARM),Release)
	$(call build_app,$(TARGET_WIN_ARM),ReleaseSmall,Release,$(APP_RELEASE))

windows-arm-debug:
	$(call build_mbedtls,$(TARGET_WIN_ARM),Debug)
	$(call build_libssh2,$(TARGET_WIN_ARM),Debug)
	$(call build_app,$(TARGET_WIN_ARM),Debug,Debug,$(APP_DEBUG))

# Cross-compile everything
cross: macos linux windows linux-arm windows-arm
