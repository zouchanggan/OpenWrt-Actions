#!/usr/bin/env bash
#=================================================
#   OpenWrt X86_64 DIY 编译脚本（优化版，无 kernel-doc 下载）
#=================================================
set -euo pipefail
IFS=$'\n\t'
# ---------- 1️⃣ 全局变量 ----------
: "${MIRROR:=https://raw.githubusercontent.com/grandway2025/OpenWRT-Action/main}"
: "${GITEA:=git.kejizero.online/zhao}"
: "${GITEA:=}"  
: "${GITHUB:=github.com}"
: "${CLASH_KERNEL:=amd64}"
KVER=6.6   # 如需升级内核，只改这里
# ---------- 2️⃣ 日志 / 错误 ----------
log()    { echo -e "\033[1;34m[INFO]  $*\033[0m"; echo "::group::$*"; }
log_end(){ echo "::endgroup::"; }
err()    { echo -e "\033[1;31m[ERROR] $*\033[0m" >&2; echo "::error::$*"; exit 1; }
# ---------- 3️⃣ 通用函数 ----------
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
# ---------- 4️⃣ 编译优化 ----------
log "Set compiler optimization"
sed -i 's/^EXTRA_OPTIMIZATION=.*/EXTRA_OPTIMIZATION=-O2 -march=x86-64-v2/' include/target.mk
log_end
# ---------- 5️⃣ Kernel & vermagic ----------
log "Skip kernel doc download (not required)"
# 保留 vermagic 生成逻辑
sed -i 's/^\(.\).*vermagic$/\1cp $(TOPDIR)\/.vermagic $(LINUX_DIR)\/.vermagic/' \
      include/kernel-defaults.mk
# 若 vermagic 依赖 HASH，可以这样生成：
if [[ -e include/kernel-${KVER} ]]; then
    grep HASH include/kernel-${KVER} | awk -F'HASH-' '{print $2}' | awk '{print $1}' \
    | md5sum | awk '{print $1}' > .vermagic
fi
log_end
# ---------- 6️⃣ 可选功能 ----------
if [[ "${ENABLE_DOCKER:-false}"    == "true" && -f ../configs/config-docker ]]; then cat ../configs/config-docker >> .config; fi
if [[ "${ENABLE_SSRP:-false}"      == "true" && -f ../configs/config-ssrp ]]; then cat ../configs/config-ssrp >> .config; fi
if [[ "${ENABLE_PASSWALL:-false}"  == "true" && -f ../configs/config-passwall ]]; then cat ../configs/config-passwall >> .config; fi
if [[ "${ENABLE_NIKKI:-false}"     == "true" && -f ../configs/config-nikki ]]; then cat ../configs/config-nikki >> .config; fi
if [[ "${ENABLE_OPENCLASH:-false}" == "true" && -f ../configs/config-openclash ]]; then cat ../configs/config-openclash >> .config; fi
if [[ "${ENABLE_LUCKY:-false}"     == "true" && -f ../configs/config-lucky ]]; then cat ../configs/config-lucky >> .config; fi
if [[ "${ENABLE_OAF:-false}"       == "true" && -f ../configs/config-oaf ]]; then cat ../configs/config-oaf >> .config; fi
# ---------- 7️⃣ 清理 SNAPSHOT ----------
log "Cleanup snapshot tags"
sed -i 's/-SNAPSHOT//g' include/version.mk \
                 package/base-files/image-config.in
sed -i '/CONFIG_BUILDBOT/d' include/feeds.mk
sed -i 's/;)\s*\\/; \\/' include/feeds.mk
log_end
# ---------- 8️⃣ 第三方 feed / packages ----------
log "Replace nginx (latest)"
rm -rf feeds/packages/net/nginx
git clone "https://${GITHUB}/sbwml/feeds_packages_net_nginx.git" \
          feeds/packages/net/nginx -b openwrt-24.10
sed -i 's/procd_set_param stdout 1/procd_set_param stdout 0/' feeds/packages/net/nginx/files/nginx.init
sed -i 's/procd_set_param stderr 1/procd_set_param stderr 0/' feeds/packages/net/nginx/files/nginx.init
curl -fsSL "${MIRROR}/Customize/nginx/luci.locations" \
      > feeds/packages/net/nginx/files-luci-support/luci.locations
curl -fsSL "${MIRROR}/Customize/nginx/uci.conf.template" \
      > feeds/packages/net/nginx-util/files/uci.conf.template
log "uwsgi performance tweaks"
sed -i '$a cgi-timeout = 600' feeds/packages/net/uwsgi/files-luci-support/luci-*.ini
sed -i '/limit-as/c\limit-as = 5000' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i 's/procd_set_param stderr 1/procd_set_param stderr 0/' \
       feeds/packages/net/uwsgi/files/uwsgi.init
sed -i -e 's/threads = 1/threads = 2/' \
       -e 's/processes = 3/processes = 4/' \
       -e 's/cheaper = 1/cheaper = 2/' \
       feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
log "rpcd timeout fix"
sed -i 's/option timeout 30/option timeout 60/' \
       package/system/rpcd/files/rpcd.config
sed -i 's#20) \* 1000#60) \* 1000#g' \
       feeds/luci/modules/luci-base/htdocs/luci-static/resources/rpc.js
log_end
# ---------- 9️⃣ 默认 IP & root 密码 ----------
log "Set default LAN address & root password"
sed -i "s/192.168.1.1/${LAN}/" package/base-files/files/bin/config_generate
if [[ -n "${ROOT_PASSWORD:-}" ]]; then
  pass_hash=$(openssl passwd -5 "${ROOT_PASSWORD}")
  sed -i "s|^root:[^:]*:|root:${pass_hash}:|" \
         package/base-files/files/etc/shadow
fi
log_end
# ---------- 10️⃣ OpenAppFilter eBPF ----------
if [[ "${ENABLE_OAF:-false}" == "true" ]]; then
  log "Enable BPF syscall for OpenAppFilter"
  sed -i 's/# CONFIG_BPF_SYSCALL is not set/CONFIG_BPF_SYSCALL=y/' .config
  log_end
fi
# ---------- 11️⃣ Rust 编译参数 ----------
log "Disable rust llvm download"
sed -i 's/--set=llvm\.download-ci-llvm=true/--set=llvm.download-ci-llvm=false/' \
       feeds/packages/lang/rust/Makefile
log_end
# ---------- 12️⃣ 第三方包 ----------
log "Clone extra packages (parallel)"
declare -A EXTRA_PKGS=(
  [nft-fullcone]="https://${GITEA}/nft-fullcone"
  [nat6]="https://${GITHUB}/sbwml/packages_new_nat6"
  [natflow]="https://${GITHUB}/sbwml/package_new_natflow"
  [shortcut-fe]="https://${GITEA}/shortcut-fe"
  [caddy]="https://${GITEA}/luci-app-caddy"
  [mosdns]="https://${GITHUB}/sbwml/luci-app-mosdns"
  [OpenAppFilter]="https://${GITHUB}/destan19/OpenAppFilter"
  [luci-app-poweroffdevice]="https://${GITHUB}/sirpdboy/luci-app-poweroffdevice"
)
declare -A EXTRA_BRANCHES=(
  [mosdns]="v5"
)
for pkg in "${!EXTRA_PKGS[@]}"; do
  repo="${EXTRA_PKGS[$pkg]}"
  branch="${EXTRA_BRANCHES[$pkg]:-}"   # ★ 用默认值方式安全访问（空字符串）
  clone_pkg "$repo" "package/new/$pkg" "$branch" &
done
wait
log_end
# ---------- 13️⃣ 生成 final .config ----------
log "Run make defconfig"
make defconfig
log_end
# ---------- 14️⃣ 输出关键变量至 workflow ----------
DEVICE_TARGET=$(grep ^CONFIG_TARGET_BOARD .config | cut -d'"' -f2)
DEVICE_SUBTARGET=$(grep ^CONFIG_TARGET_SUBTARGET .config | cut -d'"' -f2)
cat <<EOF >> "$GITHUB_ENV"
DEVICE_TARGET=$DEVICE_TARGET
DEVICE_SUBTARGET=$DEVICE_SUBTARGET
EOF
log "DIY script finished ✅"
exit 0
