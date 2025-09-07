#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
# ---------- 1️⃣ 全局变量 ----------
: "${MIRROR:=https://raw.githubusercontent.com/zouchanggan/OpenWrt-Actions/main}"
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
# ----------- 编译优化和内核设置 -----------
log "Compiler optimization & kernel vermagic"
sed -i "s/^EXTRA_OPTIMIZATION=.*/EXTRA_OPTIMIZATION=-O2 -march=x86-64-v2/" include/target.mk
download "$MIRROR/doc/kernel-$KVER" "include/kernel-$KVER"
download "$MIRROR/doc/patch/kernel-$KVER/kernel/0001-linux-module-video.patch" "package/0001-linux-module-video.patch"
apply_patch "package/0001-linux-module-video.patch"
sed -i 's/^\(.\).*vermagic$/\1cp $(TOPDIR)\/.vermagic $(LINUX_DIR)\/.vermagic/' include/kernel-defaults.mk
grep HASH "include/kernel-$KVER" | awk -F'HASH-' '{print $2}' | awk '{print $1}' | md5sum | awk '{print $1}' > .vermagic
log_end
# ----------- 合并各类功能配置 -----------
log "Merge feature configs"
[[ "$ENABLE_DOCKER"    == "true" ]] && download "$MIRROR/configs/config-docker" .config
[[ "$ENABLE_SSRP"      == "true" ]] && download "$MIRROR/configs/config-ssrp"   .config
[[ "$ENABLE_PASSWALL"  == "true" ]] && download "$MIRROR/configs/config-passwall" .config
[[ "$ENABLE_NIKKI"     == "true" ]] && download "$MIRROR/configs/config-nikki" .config
[[ "$ENABLE_OPENCLASH" == "true" ]] && download "$MIRROR/configs/config-openclash" .config
[[ "$ENABLE_LUCKY"     == "true" ]] && download "$MIRROR/configs/config-lucky" .config
[[ "$ENABLE_OAF"       == "true" ]] && download "$MIRROR/configs/config-oaf" .config
log_end
# ----------- 清理 SNAPSHOT -----------
log "Fix version string / snapshot tag"
sed -i 's/-SNAPSHOT//g' include/version.mk package/base-files/image-config.in
sed -i '/CONFIG_BUILDBOT/d' include/feeds.mk
sed -i 's/;)\s*\\/; \\/' include/feeds.mk
log_end
# ----------- 内核/BBR/LRNG/Firewall4/NFT补丁 ----------
log "Kernel, BBR, LRNG, firewall4, nft, luci-firewall, shortcut等全部定制补丁"
# BBR
pushd target/linux/generic/backport-$KVER
for i in $(seq -w 1 18); do
    patch_url="$MIRROR/doc/patch/kernel-$KVER/bbr3/010-00${i}-*.patch"
    download "$patch_url" "$(basename $patch_url)"
done
popd
# Kernel olddefconfig
download "$MIRROR/doc/patch/kernel-$KVER/kernel/0003-include-kernel-defaults.mk.patch" "/tmp/kernel-defaults.patch"
patch -p1 < /tmp/kernel-defaults.patch && rm -f /tmp/kernel-defaults.patch
# LRNG
cat >> ./target/linux/generic/config-$KVER <<EOF
# CONFIG_RANDOM_DEFAULT_IMPL is not set
CONFIG_LRNG=y
CONFIG_LRNG_DEV_IF=y
# CONFIG_LRNG_IRQ is not set
CONFIG_LRNG_JENT=y
CONFIG_LRNG_CPU=y
# CONFIG_LRNG_SCHED is not set
CONFIG_LRNG_SELFTEST=y
# CONFIG_LRNG_SELFTEST_PANIC is not set
EOF
pushd target/linux/generic/hack-$KVER
for i in $(seq -w 1 27); do
    patch_url="$MIRROR/doc/patch/kernel-$KVER/lrng/696-${i}-*.patch"
    download "$patch_url" "$(basename $patch_url)"
done
popd
# firewall4、fullcone、bcc、offload等
mkdir -p package/network/config/firewall4/patches
download "$MIRROR/Customize/firewall4/Makefile" package/network/config/firewall4/Makefile
sed -i 's|$(PROJECT_GIT)/project|https://github.com/openwrt|g' package/network/config/firewall4/Makefile
for patch in 990-unconditionally-allow-ct-status-dnat 001-fix-fw4-flow-offload 999-01-firewall4-add-fullcone-support 999-02-firewall4-add-bcm-fullconenat-support; do
    download "$MIRROR/doc/patch/firewall4/firewall4_patches/$patch.patch" "package/network/config/firewall4/patches/$patch.patch"
done
download "$MIRROR/doc/patch/firewall4/100-openwrt-firewall4-add-custom-nft-command-support.patch" "/tmp/firewall4-nft-custom.patch"
patch -p1 < /tmp/firewall4-nft-custom.patch && rm -f /tmp/firewall4-nft-custom.patch
# libnftnl
mkdir -p package/libs/libnftnl/patches
for patch in 0001-libnftnl-add-fullcone-expression-support 0002-libnftnl-add-brcm-fullcone-support; do
    download "$MIRROR/doc/patch/firewall4/libnftnl/$patch.patch" "package/libs/libnftnl/patches/$patch.patch"
done
# misc kernel
for patch in \
    btf/990-btf-silence-btf-module-warning-messages \
    arm64/312-arm64-cpuinfo-Add-model-name-in-proc-cpuinfo-for-64bit-ta \
    net/952-net-conntrack-events-support-multiple-registrant \
    net/982-add-bcm-fullcone-support \
    net/983-add-bcm-fullcone-nft_masq-support \
    net/601-netfilter-export-udp_get_timeouts-function \
    net/953-net-patch-linux-kernel-to-support-shortcut-fe
do
    patch_name=$(basename $patch)
    download "$MIRROR/doc/patch/kernel-$KVER/$patch.patch" "target/linux/generic/hack-$KVER/$patch_name.patch"
done
# nftables
mkdir -p package/network/utils/nftables/patches
for patch in 0001-nftables-add-fullcone-expression-support 0002-nftables-add-brcm-fullconenat-support 0003-drop-rej-file; do
    download "$MIRROR/doc/patch/firewall4/nftables/$patch.patch" "package/network/utils/nftables/patches/$patch.patch"
done
# LuCI firewall & luci-mod
pushd feeds/luci
for patch in \
    0001-luci-app-firewall-add-nft-fullcone-and-bcm-fullcone- \
    0002-luci-app-firewall-add-shortcut-fe-option \
    0003-luci-app-firewall-add-ipv6-nat-option \
    0004-luci-add-firewall-add-custom-nft-rule-support \
    0005-luci-app-firewall-add-natflow-offload-support \
    0006-luci-app-firewall-enable-hardware-offload-only-on-de \
    0007-luci-app-firewall-add-fullcone6-option-for-nftables-
do
    download "$MIRROR/doc/patch/firewall4/luci-24.10/$patch.patch" "/tmp/$patch.patch"
    patch -p1 < "/tmp/$patch.patch" && rm -f "/tmp/$patch.patch"
done
for patch in \
    0001-luci-mod-system-add-modal-overlay-dialog-to-reboot \
    0002-luci-mod-status-displays-actual-process-memory-usage \
    0003-luci-mod-status-storage-index-applicable-only-to-val \
    0004-luci-mod-status-firewall-disable-legacy-firewall-rul \
    0005-luci-mod-system-add-refresh-interval-setting \
    0006-luci-mod-system-mounts-add-docker-directory-mount-po \
    0007-luci-mod-system-add-ucitrack-luci-mod-system-zram.js
do
    download "$MIRROR/doc/patch/luci/$patch.patch" "/tmp/$patch.patch"
    patch -p1 < "/tmp/$patch.patch" && rm -f "/tmp/$patch.patch"
done
popd
# igc-fix
download "$MIRROR/doc/patch/kernel-$KVER/igc-fix/996-intel-igc-i225-i226-disable-eee.patch" "target/linux/x86/patches-$KVER/996-intel-igc-i225-i226-disable-eee.patch"
log_end
# ----------- 多媒体/路由器服务组件调整 -----------
log "Docker/TTYD/UPnP/profile/bash/rootfs/NTP/作者/KEY"
# Docker
rm -rf feeds/luci/applications/luci-app-dockerman
clone_pkg "https://github.com/sirpdboy/luci-app-dockerman.git" "package/new/dockerman" ""
mv -n package/new/dockerman/luci-app-dockerman feeds/luci/applications && rm -rf package/new/dockerman
for pkg in docker dockerd containerd runc; do
    rm -rf feeds/packages/utils/$pkg
    clone_pkg "https://${GITHUB}/sbwml/packages_utils_${pkg}" "feeds/packages/utils/$pkg" ""
done
# TTYD & UPnP
sed -i 's/services/system/g' feeds/luci/applications/luci-app-ttyd/root/usr/share/luci/menu.d/luci-app-ttyd.json
sed -i '3 a\\t\t"order": 50,' feeds/luci/applications/luci-app-ttyd/root/usr/share/luci/menu.d/luci-app-ttyd.json
sed -i 's/procd_set_param stdout 1/procd_set_param stdout 0/g' feeds/packages/utils/ttyd/files/ttyd.init
sed -i 's/procd_set_param stderr 1/procd_set_param stderr 0/g' feeds/packages/utils/ttyd/files/ttyd.init
rm -rf feeds/packages/net/miniupnpd feeds/luci/applications/luci-app-upnp
clone_pkg "https://${GITEA}/miniupnpd" "feeds/packages/net/miniupnpd" "v2.3.9"
clone_pkg "https://${GITEA}/luci-app-upnp" "feeds/luci/applications/luci-app-upnp" "openwrt-24.10"
# profile/bash/rootfs
sed -i 's#\\u@\\h:\\w\\\$#\\[\\e[32;1m\\][\\u@\\h\\[\\e[0m\\] \\[\\033[01;34m\\]\\W\\[\\033[00m\\]\\[\\e[32;1m\\]]\\[\\e[0m\\]\\\$#g' package/base-files/files/etc/profile
sed -ri 's/(export PATH=")[^"]*/\1%PATH%:\/opt\/bin:\/opt\/sbin:\/opt\/usr\/bin:\/opt\/usr\/sbin/' package/base-files/files/etc/profile
sed -i '/PS1/a\export TERM=xterm-color' package/base-files/files/etc/profile
sed -i 's#ash#bash#g' package/base-files/files/etc/passwd
sed -i '\#export ENV=/etc/shinit#a export HISTCONTROL=ignoredups' package/base-files/files/etc/profile
mkdir -p files/root
download "$MIRROR/doc/files/root/.bash_profile" "files/root/.bash_profile"
download "$MIRROR/doc/files/root/.bashrc" "files/root/.bashrc"
mkdir -p files/etc/sysctl.d files/bin
for f in 10-default.conf 15-vm-swappiness.conf 16-udp-buffer-size.conf; do
    download "$MIRROR/doc/files/etc/sysctl.d/$f" "files/etc/sysctl.d/$f"
done
download "$MIRROR/doc/files/root/version.txt" "files/root/version.txt"
download "$MIRROR/doc/files/bin/ZeroWrt" "files/bin/ZeroWrt"
chmod +x files/bin/ZeroWrt
chmod 644 files/root/version.txt
download "https://opkg.kejizero.online/key-build.pub" "files/root/key-build.pub"
chmod 644 files/root/key-build.pub
# NTP
sed -i 's/0.openwrt.pool.ntp.org/ntp1.aliyun.com/g' package/base-files/files/bin/config_generate
sed -i 's/1.openwrt.pool.ntp.org/ntp2.aliyun.com/g' package/base-files/files/bin/config_generate
sed -i 's/2.openwrt.pool.ntp.org/time1.cloud.tencent.com/g' package/base-files/files/bin/config_generate
sed -i 's/3.openwrt.pool.ntp.org/time2.cloud.tencent.com/g' package/base-files/files/bin/config_generate
# 作者信息
sed -i "s/DISTRIB_DESCRIPTION='*.*'/DISTRIB_DESCRIPTION='OpenWrt-$(date +%Y%m%d)'/g"  package/base-files/files/etc/openwrt_release
sed -i "s/DISTRIB_REVISION='*.*'/DISTRIB_REVISION=' By grandway2025'/g" package/base-files/files/etc/openwrt_release
sed -i "s|^OPENWRT_RELEASE=\".*\"|OPENWRT_RELEASE=\"OpenWrt定制版 @R$(date +%Y%m%d) BY grandway2025\"|" package/base-files/files/usr/lib/os-release
sed -i "/BUILD_DATE/d" package/base-files/files/usr/lib/os-release
sed -i "/BUILD_ID/aBUILD_DATE=\"$(date +%Y-%m-%d)\"" package/base-files/files/usr/lib/os-release
log_end
# ----------- 其它服务应用（ddns、frpc、natmap、luci及主题、samba等） ----------
log "Network, storage, and applications (ddns, frp, natmap, samba, argon, unzip, openlist, etc)"
# DDNS
sed -i '/boot()/,+2d' feeds/packages/net/ddns-scripts/files/etc/init.d/ddns
# frpc
sed -i 's/procd_set_param stdout $stdout/procd_set_param stdout 0/g' feeds/packages/net/frp/files/frpc.init
sed -i 's/procd_set_param stderr $stderr/procd_set_param stderr 0/g' feeds/packages/net/frp/files/frpc.init
sed -i 's/stdout stderr //g' feeds/packages/net/frp/files/frpc.init
sed -i '/stdout:bool/d;/stderr:bool/d' feeds/packages/net/frp/files/frpc.init
sed -i '/stdout/d;/stderr/d' feeds/packages/net/frp/files/frpc.config
sed -i 's/env conf_inc/env conf_inc enable/g' feeds/packages/net/frp/files/frpc.init
sed -i "s/'conf_inc:list(string)'/& \\\\/" feeds/packages/net/frp/files/frpc.init
sed -i "/conf_inc:list/a\\\t\t\'enable:bool:0\'" feeds/packages/net/frp/files/frpc.init
sed -i '/procd_open_instance/i\\t\[ "$enable" -ne 1 \] \&\& return 1\n' feeds/packages/net/frp/files/frpc.init
for patch in 001-luci-app-frpc-hide-token 002-luci-app-frpc-add-enable-flag; do
    download "$MIRROR/Customize/frpc/$patch.patch" "/tmp/$patch.patch"
    patch -p1 < "/tmp/$patch.patch" && rm -f "/tmp/$patch.patch"
done
# natmap
sed -i 's/log_stdout:bool:1/log_stdout:bool:0/g;s/log_stderr:bool:1/log_stderr:bool:0/g' feeds/packages/net/natmap/files/natmap.init
pushd feeds/luci
download "$MIRROR/Customize/natmap/0001-luci-app-natmap-add-default-STUN-server-lists.patch" "/tmp/natmap-server-list.patch"
patch -p1 < /tmp/natmap-server-list.patch && rm -f /tmp/natmap-server-list.patch
popd
# samba4
rm -rf feeds/packages/net/samba4
clone_pkg "https://${GITHUB}/sbwml/feeds_packages_net_samba4" "feeds/packages/net/samba4" ""
sed -i '/workgroup/a \\n\t## enable multi-channel' feeds/packages/net/samba4/files/smb.conf.template
sed -i '/enable multi-channel/a \\tserver multi channel support = yes' feeds/packages/net/samba4/files/smb.conf.template
sed -i 's/#aio read size = 0/aio read size = 0/g' feeds/packages/net/samba4/files/smb.conf.template
sed -i 's/#aio write size = 0/aio write size = 0/g' feeds/packages/net/samba4/files/smb.conf.template
sed -i 's/invalid users = root/#invalid users = root/g' feeds/packages/net/samba4/files/smb.conf.template
sed -i 's/bind interfaces only = yes/bind interfaces only = no/g' feeds/packages/net/samba4/files/smb.conf.template
sed -i 's/#create mask/create mask/g' feeds/packages/net/samba4/files/smb.conf.template
sed -i 's/#directory mask/directory mask/g' feeds/packages/net/samba4/files/smb.conf.template
sed -i 's/0666/0644/g;s/0744/0755/g;s/0777/0755/g' feeds/luci/applications/luci-app-samba4/htdocs/luci-static/resources/view/samba4.js
sed -i 's/0666/0644/g;s/0777/0755/g' feeds/packages/net/samba4/files/samba.config
sed -i 's/0666/0644/g;s/0777/0755/g' feeds/packages/net/samba4/files/smb.conf.template
# SSR(P)&Passwall
rm -rf feeds/packages/net/{xray-core,v2ray-core,v2ray-geodata,sing-box}
clone_pkg "https://${GITHUB}/sbwml/openwrt_helloworld" "package/new/helloworld" "v5"
# openlist & unzip & argon-theme
clone_pkg "https://${GITHUB}/sbwml/luci-app-openlist2" "package/new/openlist" ""
rm -rf feeds/packages/utils/unzip
clone_pkg "https://${GITHUB}/sbwml/feeds_packages_utils_unzip" "feeds/packages/utils/unzip" ""
rm -rf feeds/luci/themes/luci-theme-argon
clone_pkg "https://github.com/grandway2025/argon" "package/new/luci-theme-argon" ""
for f in footer.ut footer_login.ut; do
    sed -i 's|<a class="luci-link" href="https://github.com/openwrt/luci" target="_blank">Powered by {{ version.luciname }} ({{ version.luciversion }})</a>|<a class="luci-link" href="https://github.com/grandway2025" target="_blank">OpenWrt定制版</a>|g' "package/new/luci-theme-argon/ucode/template/themes/argon/$f"
done
# Go 1.24/luci-app-webdav/quickfile
rm -rf feeds/packages/lang/golang
clone_pkg "https://${GITHUB}/sbwml/packages_lang_golang" "feeds/packages/lang/golang" "24.x"
clone_pkg "https://${GITHUB}/sbwml/luci-app-webdav" "package/new/luci-app-webdav" ""
clone_pkg "https://${GITHUB}/sbwml/luci-app-quickfile" "package/new/quickfile" ""
log_end
# ----------- 默认IP/密码/root权限优化等 -----------
log "LAN IP & root password"
sed -i "s/192.168.1.1/${LAN}/" package/base-files/files/bin/config_generate
if [[ -n "${ROOT_PASSWORD}" ]]; then
  pass_hash=$(openssl passwd -5 "${ROOT_PASSWORD}")
  sed -i "s|^root:[^:]*:|root:${pass_hash}:|" package/base-files/files/etc/shadow
fi
log_end
# ----------- OAF eBPF选项 ----------
if [[ "$ENABLE_OAF" == "true" ]]; then
  log "Enable BPF SYSCALL for OpenAppFilter"
  sed -i 's/# CONFIG_BPF_SYSCALL is not set/CONFIG_BPF_SYSCALL=y/' .config
  log_end
fi
# ----------- Rust补丁 -----------
log "Patch Rust to skip llvm download"
sed -i 's/--set=llvm\.download-ci-llvm=true/--set=llvm.download-ci-llvm=false/' feeds/packages/lang/rust/Makefile
log_end
# ----------- 构建最终 .config ----------
log "Run make defconfig"
make defconfig
log_end
DEVICE_TARGET=$(grep ^CONFIG_TARGET_BOARD .config | cut -d'"' -f2)
DEVICE_SUBTARGET=$(grep ^CONFIG_TARGET_SUBTARGET .config | cut -d'"' -f2)
cat <<EOF >> "$GITHUB_ENV"
DEVICE_TARGET=$DEVICE_TARGET
DEVICE_SUBTARGET=$DEVICE_SUBTARGET
EOF
log "DIY script finished ✅"
exit 0
