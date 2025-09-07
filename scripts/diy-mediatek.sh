#!/usr/bin/env bash
#================================================================
#  OpenWrt Mediatek (mt7986) DIY 编译脚本
#  目标：可读、可靠、高效
#================================================================
set -euo pipefail
IFS=$'\n\t'
# ------------------- 1️⃣ 全局变量 -------------------
: "${MIRROR:=https://mirrors.tuna.tsinghua.edu.cn/openwrt}"
: "${GITEA:=git.kejizero.online/zhao}"
: "${GITHUB:=github.com}"
: "${CLASH_KERNEL:=amd64}"
KVER=6.6   # 若需升级只改这里
# ------------------- 2️⃣ 日志 / 错误 -------------------
log()    { echo -e "\033[1;34m[INFO]  $*\033[0m"; echo "::group::$*"; }
log_end(){ echo "::endgroup::"; }
err()    { echo -e "\033[1;31m[ERROR] $*\033[0m" >&2; echo "::error::$*"; exit 1; }
# ------------------- 3️⃣ 通用函数 -------------------
download() {
  local url=$1 dst=$2
  curl -fsSL --retry 3 --retry-delay 5 "$url" -o "$dst" \
    || err "download failed: $url"
  [[ -s "$dst" ]] || err "download produced empty file: $dst"
}
apply_patch() {
  local f=$1
  if git apply "$f"; then rm -f "$f"; else err "apply patch failed: $f"; fi
}
clone_pkg() {
  local repo=$1 dst=$2 branch=$3
  if [[ -n $branch ]]; then
    git clone --depth=1 -b "$branch" "$repo" "$dst" \
      || err "clone $repo (branch $branch) failed"
  else
    git clone --depth=1 "$repo" "$dst" \
      || err "clone $repo failed"
  fi
}
# ------------------- 4️⃣ 基础配置（IP、默认名称、TTYD） -------------------
log "基础配置：LAN IP、默认名称、TTYD免登录"
sed -i "s|192\\.168\\.6\\.1|${LAN}|g" package/base-files/files/bin/config_generate
sed -i 's/ImmortalWrt/OpenWrt/' package/base-files/files/bin/config_generate
sed -i 's|/bin/login|/bin/login -f root|g' \
       feeds/packages/utils/ttyd/files/ttyd.config
log_end
# ------------------- 5️⃣ root 密码（若提供） -------------------
if [[ -n "${ROOT_PASSWORD:-}" ]]; then
  log "设置 root 密码（sha256）"
  pass_hash=$(openssl passwd -5 "$ROOT_PASSWORD")
  sed -i "s|^root:[^:]*:|root:${pass_hash}:|" \
         package/base-files/files/etc/shadow
  log_end
fi
# ------------------- 6️⃣ 删除不需要的网络 & luci 包 -------------------
log "删除默认 feed 中不需要的包"
rm -rf feeds/packages/net/{v2ray-geodata,open-app-filter,shadowsocksr-libev,shadowsocks-rust,shadowsocks-libev,\
tcping,trojan,trojan-plus,tuic-client,v2ray-core,v2ray-plugin,xray-core,xray-plugin,\
sing-box,chinadns-ng,hysteria,mosdns,lucky,ddns-go,v2dat,golang}
rm -rf feeds/luci/applications/{luci-app-daed,luci-app-dae,luci-app-homeproxy,luci-app-openclash,\
luci-app-passwall,luci-app-passwall2,luci-app-ssr-plus,luci-app-vssr,\
luci-app-appfilter,luci-app-ddns-go,luci-app-lucky,luci-app-mosdns,luci-app-alist,\
luci-app-openlist,luci-app-airwhu}
log_end
# ------------------- 7️⃣ 固件描述信息 -------------------
log "写入自定义描述"
sed -i "s/DISTRIB_DESCRIPTION='.*'/DISTRIB_DESCRIPTION='OpenWrt-$(date +%Y%m%d)'/" \
       package/base-files/files/etc/openwrt_release
sed -i "s/DISTRIB_REVISION='.*'/DISTRIB_REVISION=' By grandway2025'/" \
       package/base-files/files/etc/openwrt_release
sed -i "s|^OPENWRT_RELEASE=\".*\"|OPENWRT_RELEASE=\"OpenWrt定制版 \"|" \
       package/base-files/files/usr/lib/os-release
log_end
# ------------------- 8️⃣ Argon 主题（一次性替换） -------------------
log "替换 Argon 主题"
rm -rf feeds/luci/themes/luci-theme-argon
git clone https://github.com/grandway2025/argon \
          package/new/luci-theme-argon --depth=1
log_end
# ------------------- 9️⃣ Go 1.25（统一替换） -------------------
log "替换 golang 为 1.25"
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 25.x \
          feeds/packages/lang/golang
log_end
# ------------------- 10️⃣ 第三方插件并行克隆 -------------------
log "并行克隆额外插件"
declare -A EXTRA_PKGS=(
  [helloworld]="https://${GITHUB}/grandway2025/helloworld -b openwrt-24.10"
  [lucky]="https://${GITHUB}/gdy666/luci-app-lucky"
  [mosdns]="https://${GITHUB}/sbwml/luci-app-mosdns -b v5"
  [OpenAppFilter]="https://${GITHUB}/destan19/OpenAppFilter"
  [luci-app-taskplan]="https://${GITHUB}/sirpdboy/luci-app-taskplan"
  [luci-app-webdav]="https://${GITHUB}/sbwml/luci-app-webdav -b openwrt-24.10"
  [quickfile]="https://${GITHUB}/sbwml/luci-app-quickfile"
  [openlist]="https://${GITHUB}/sbwml/luci-app-openlist2"
  [luci-app-socat]="https://${GITHUB}/zhiern/luci-app-socat"
  [luci-app-adguardhome]="https://git.kejizero.online/zhao/luci-app-adguardhome"
)
for pkg in "${!EXTRA_PKGS[@]}"; do
  url=${EXTRA_PKGS[$pkg]}
  repo=$(awk '{print $1}' <<<"$url")
  branch=$(awk '{print $2}' <<<"$url")
  clone_pkg "$repo" "package/new/$pkg" "$branch" &
done
wait
log_end
# ------------------- 11️⃣ AdGuardHome 二进制 -------------------
log "下载 AdGuardHome（ARM64）"
mkdir -p files/usr/bin
AGH_URL=$(curl -fsSL "https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest" \
          | grep browser_download_url | grep linux_arm64 | cut -d'"' -f4)
curl -fsSL "$AGH_URL" -o /tmp/adh.tar.gz
tar -xzf /tmp/adh.tar.gz -C files/usr/bin --strip-components=1 AdGuardHome/AdGuardHome
chmod +x files/usr/bin/AdGuard
log_end
# ------------------- 12️⃣ OpenClash 二进制 & GEOIP/GEOSITE -------------------
log "下载 OpenClash core 与规则数据"
mkdir -p files/etc/openclash/core
CLASH_META="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
GEOIP_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/geoip.dat"
GEOSITE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
curl -fsSL "$CLASH_META" | tar -xz -C files/etc/openclash/core clash
curl -fsSL "$GEOIP_URL"    -o files/etc/openclash/GeoIP.dat
curl -fsSL "$GEOSITE_URL"  -o files/etc/openclash/GeoSite.dat
chmod +x files/etc/openclash/core/clash*
log_end
# ------------------- 13️⃣ Docker 相关工具 -------------------
log "替换 Docker 相关 utility"
rm -rf feeds/luci/applications/luci-app-dockerman
git clone https://github.com/sirpdboy/luci-app-dockerman.git \
          package/new/dockerman --depth=1
mv -n package/new/dockerman/luci-app-dockerman feeds/luci/applications && rm -rf package/new/dockerman
rm -rf feeds/packages/utils/{docker,dockerd,containerd,runc}
git clone https://github.com/sbwml/packages_utils_docker      feeds/packages/utils/docker      --depth=1
git clone https://github.com/sbwml/packages_utils_dockerd    feeds/packages/utils/dockerd    --depth=1
git clone https://github.com/sbwml/packages_utils_containerd feeds/packages/utils/containerd --depth=1
git clone https://github.com/sbwml/packages_utils_runc       feeds/packages/utils/runc       --depth=1
log_end
# ------------------- 14️⃣ default‑settings -------------------
log "拉取自定义 default‑settings（meditatek 分支）"
rm -rf package/emortal/default-settings
git clone -b mediatek https://github.com/grandway2025/default-settings \
          package/new/default-settings --depth=1
log_end
# ------------------- 15️⃣ 生成 final .config -------------------
log "执行 make defconfig 生成完整配置"
make defconfig
log_end
# ------------------- 16️⃣ 导出关键变量至 workflow -------------------
DEVICE_TARGET=$(grep ^CONFIG_TARGET_BOARD .config | cut -d'"' -f2)
DEVICE_SUBTARGET=$(grep ^CONFIG_TARGET_SUBTARGET .config | cut -d'"' -f2)
cat <<EOF >> "$GITHUB_ENV"
DEVICE_TARGET=$DEVICE_TARGET
DEVICE_SUBTARGET=$DEVICE_SUBTARGET
LAN=$LAN
ROOT_PASSWORD=$ROOT_PASSWORD
EOF
log "DIY 脚本执行完毕 ✅"
exit 0   # 正常退出（不要写文件名当返回码）
