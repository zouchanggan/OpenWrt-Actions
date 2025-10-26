#!/bin/bash
#=================================================
# 预编译工具链智能加载脚本
# 功能：自动检测配置并智能回退加载工具链
# 位置：scripts/diy-toolchain.sh
#=================================================

# 颜色定义
RED_COLOR='\033[1;31m'
GREEN_COLOR='\033[1;32m'
YELLOW_COLOR='\033[1;33m'
BLUE_COLOR='\033[1;34m'
RES='\033[0m'

# 下载进度条
if curl --help | grep progress-bar >/dev/null 2>&1; then
    CURL_BAR="--progress-bar"
fi

echo -e ""
echo -e "${BLUE_COLOR}════════════════════════════════════════════════════════════════${RES}"
echo -e "${BLUE_COLOR}              PREBUILT TOOLCHAIN LOADER                         ${RES}"
echo -e "${BLUE_COLOR}════════════════════════════════════════════════════════════════${RES}"

# 检查是否启用预编译工具链
if [ "$BUILD_FAST" != "y" ] && [ "$ENABLE_PREBUILT_TOOLCHAIN" != "y" ]; then
    echo -e "${YELLOW_COLOR}ℹ️  Prebuilt Toolchain Disabled${RES}"
    echo -e "${YELLOW_COLOR}   Set BUILD_FAST=y or ENABLE_PREBUILT_TOOLCHAIN=y to enable${RES}"
    echo -e "${BLUE_COLOR}════════════════════════════════════════════════════════════════${RES}"
    echo -e ""
    exit 0
fi

# 工具链配置
TOOLCHAIN_ARCH="x86_64"
TOOLCHAIN_URL="https://github.com/${GITHUB_REPOSITORY:-zouchanggan/OpenWrt-Actions}/releases/download/openwrt-24.10"

echo -e "  📦 Architecture: ${YELLOW_COLOR}${TOOLCHAIN_ARCH}${RES}"
echo -e "${BLUE_COLOR}════════════════════════════════════════════════════════════════${RES}"
echo -e ""

# 🔥 从 .config 自动检测配置
LIBC="musl"
GCC_VERSION="15"

if [ -f ".config" ]; then
    echo -e "${GREEN_COLOR}🔍 Auto-detecting configuration from .config...${RES}"
    grep -q "CONFIG_LIBC_USE_GLIBC=y" .config && LIBC="glibc"
    grep -q "CONFIG_GCC_USE_VERSION_13=y" .config && GCC_VERSION="13"
    grep -q "CONFIG_GCC_USE_VERSION_14=y" .config && GCC_VERSION="14"
    echo -e "   Detected: ${YELLOW_COLOR}${LIBC} / GCC-${GCC_VERSION}${RES}"
else
    echo -e "${YELLOW_COLOR}⚠️  .config not found, using defaults: ${LIBC} / GCC-${GCC_VERSION}${RES}"
fi

# 智能回退版本列表
VERSIONS=("$GCC_VERSION")
[ "$GCC_VERSION" != "15" ] && VERSIONS+=("15")
[ "$GCC_VERSION" != "14" ] && VERSIONS+=("14")
[ "$GCC_VERSION" != "13" ] && VERSIONS+=("13")

echo -e ""
echo -e "${GREEN_COLOR}📥 Trying toolchain versions: ${VERSIONS[*]}${RES}"
echo -e ""

LOADED=false

# 尝试下载并加载工具链
for VER in "${VERSIONS[@]}"; do
    TOOLCHAIN_FILENAME="toolchain_${LIBC}_${TOOLCHAIN_ARCH}_gcc-${VER}.tar.zst"
    
    echo -e "${BLUE_COLOR}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RES}"
    echo -e "${GREEN_COLOR}🔧 Attempting GCC ${VER} (${LIBC})${RES}"
    echo -e "${BLUE_COLOR}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RES}"
    
    # 下载工具链（3次重试）
    DOWNLOAD_SUCCESS=false
    for attempt in 1 2 3; do
        echo -e "${YELLOW_COLOR}   📥 Download attempt $attempt/3...${RES}"
        
        if curl -L -f "${TOOLCHAIN_URL}/${TOOLCHAIN_FILENAME}" \
            -o toolchain.tar.zst \
            --connect-timeout 30 \
            --max-time 600 \
            --retry 3 \
            $CURL_BAR 2>&1; then
            DOWNLOAD_SUCCESS=true
            echo -e "${GREEN_COLOR}   ✅ Download completed${RES}"
            break
        else
            echo -e "${RED_COLOR}   ❌ Attempt $attempt failed${RES}"
            rm -f toolchain.tar.zst
            [ $attempt -lt 3 ] && sleep 10
        fi
    done
    
    if [ "$DOWNLOAD_SUCCESS" = false ]; then
        echo -e "${RED_COLOR}   ❌ Download failed after 3 attempts${RES}"
        continue
    fi
    
    # 验证压缩包
    echo -e "${YELLOW_COLOR}   🔍 Verifying archive...${RES}"
    if [ ! -f "toolchain.tar.zst" ]; then
        echo -e "${RED_COLOR}   ❌ Archive file not found${RES}"
        continue
    fi
    
    echo -e "${YELLOW_COLOR}   📊 Size: $(du -h toolchain.tar.zst | cut -f1)${RES}"
    
    if ! zstd -t toolchain.tar.zst >/dev/null 2>&1; then
        echo -e "${RED_COLOR}   ❌ Archive verification failed${RES}"
        rm -f toolchain.tar.zst
        continue
    fi
    
    echo -e "${GREEN_COLOR}   ✅ Archive verified${RES}"
    
    # 解压工具链
    echo -e "${YELLOW_COLOR}   📦 Extracting toolchain...${RES}"
    if tar -I "zstd -d -T0" -xf toolchain.tar.zst 2>&1 | grep -v "Ignoring unknown" || true; then
        rm -f toolchain.tar.zst
        
        # 更新时间戳
        echo -e "${YELLOW_COLOR}   🔧 Processing files...${RES}"
        mkdir -p bin
        find ./staging_dir/ -name '*' -exec touch {} \; >/dev/null 2>&1 || true
        find ./tmp/ -name '*' -exec touch {} \; >/dev/null 2>&1 || true
        
        # 验证工具链
        TOOLCHAIN_DIR=$(find staging_dir -maxdepth 1 -type d -name "toolchain-*" 2>/dev/null | head -1)
        if [ -n "$TOOLCHAIN_DIR" ] && [ -d "$TOOLCHAIN_DIR" ]; then
            GCC_BIN=$(find "$TOOLCHAIN_DIR/bin" -name "*-gcc" -type f 2>/dev/null | head -1)
            if [ -n "$GCC_BIN" ] && [ -f "$GCC_BIN" ]; then
                chmod +x "$GCC_BIN" 2>/dev/null || true
                if GCC_VER=$("$GCC_BIN" --version 2>&1 | head -1); then
                    echo -e "${GREEN_COLOR}   ✅ Verified: ${GCC_VER}${RES}"
                    echo -e ""
                    echo -e "${GREEN_COLOR}╔════════════════════════════════════════════════════════════╗${RES}"
                    echo -e "${GREEN_COLOR}║           ✅ TOOLCHAIN READY - SAVING ~25 MINUTES         ║${RES}"
                    echo -e "${GREEN_COLOR}╚════════════════════════════════════════════════════════════╝${RES}"
                    export TOOLCHAIN_READY=true
                    LOADED=true
                    break
                fi
            fi
        fi
    fi
    
    # 清理失败的文件
    echo -e "${RED_COLOR}   ❌ Toolchain validation failed${RES}"
    rm -f toolchain.tar.zst
done

echo -e ""
echo -e "${BLUE_COLOR}════════════════════════════════════════════════════════════════${RES}"

if [ "$LOADED" = true ]; then
    echo -e "${GREEN_COLOR}✅ Prebuilt toolchain loaded successfully${RES}"
    echo -e "${BLUE_COLOR}════════════════════════════════════════════════════════════════${RES}"
    echo -e ""
    exit 0
else
    echo -e "${YELLOW_COLOR}⚠️  No compatible prebuilt toolchain found${RES}"
    echo -e "${YELLOW_COLOR}   Will build toolchain from source (~25 minutes extra)${RES}"
    echo -e "${BLUE_COLOR}════════════════════════════════════════════════════════════════${RES}"
    echo -e ""
    exit 0
fi
