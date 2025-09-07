#!/usr/bin/env bash
#=================================================
#   OpenWrt X86_64 DIY 融合脚本 (进阶版)
#=================================================
set -euo pipefail
IFS=$'\n\t'
# ---------- 1️⃣ 全局变量 ----------
: "${MIRROR:=https://raw.githubusercontent.com/grandway2025/OpenWRT-Action/main}"
: "${GITEA:=git.kejizero.online/zhao}"
: "${GITHUB:=github.com}"
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
sed -i 's/^\(.\).*vermagic$/\1cp $(TOPDIR)\/.vermagic $(LINUX_DIR)\/.vermagic/' include/kernel-defaults.mk
if [[ -e include/kernel-${KVER} ]]; then
    grep HASH include/kernel-${KVER} | awk -F'HASH-' '{print $2}' | awk '{print $1}' \
    | md5sum | awk '{print $1}' > .vermagic
fi
log_end
# ---------- 6️⃣ 导入外部.config功能块配置 ----------
for feat in docker ssrp passwall nikki openclash lucky oaf adguardhome mosdns openlist taskplan advancedplus; do
    vname="ENABLE_${feat^^}"
    vval="${!vname:-false}"
    cfgfile="../configs/config-$feat"
    if [[ "${vval,,}" == "true" && -f $cfgfile ]]; then
        cat "$cfgfile" >> .config
    fi
done
log_end
# ---------- 7️⃣ 清理 SNAPSHOT ----------
log "Cleanup snapshot tags"
sed -i 's/-SNAPSHOT//g' include/version.mk  package/base-files/image-config.in
sed -i '/CONFIG_BUILDBOT/d' include/feeds.mk
sed -i 's/;)\s*\\/; \\/' include/feeds.mk
log_end
# ---------- 8️⃣ 第三方 feed / packages ----------
log "Replace nginx (latest) and tune"
rm -rf feeds/packages/net/nginx
git clone "https://${GITHUB}/sbwml/feeds_packages_net_nginx.git" feeds/packages/net/nginx -b openwrt-24.10
sed -i 's/procd_set_param stdout 1/procd_set_param stdout 0/' feeds/packages/net/nginx/files/nginx.init
sed -i 's/procd_set_param stderr 1/procd_set_param stderr 0/' feeds/packages/net/nginx/files/nginx.init
curl -fsSL "${MIRROR}/Customize/nginx/luci.locations" > feeds/packages/net/nginx/files-luci-support/luci.locations
curl -fsSL "${MIRROR}/Customize/nginx/uci.conf.template" > feeds/packages/net/nginx-util/files/uci.conf.template
log "uwsgi performance tweaks"
sed -i '$a cgi-timeout = 600' feeds/packages/net/uwsgi/files-luci-support/luci-*.ini
sed -i '/limit-as/c\limit-as = 5000' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i 's/procd_set_param stderr 1/procd_set_param stderr 0/' feeds/packages/net/uwsgi/files/uwsgi.init
sed -i -e 's/threads = 1/threads = 2/' -e 's/processes = 3/processes = 4/' -e 's/cheaper = 1/cheaper = 2/' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
log "rpcd timeout fix"
sed -i 's/option timeout 30/option timeout 60/' package/system/rpcd/files/rpcd.config
sed -i 's#20) \* 1000#60) \* 1000#g' feeds/luci/modules/luci-base/htdocs/luci-static/resources/rpc.js
log_end
# ---------- 9️⃣ 必须补丁/新 kernel&fw 相关 patch（按目录分组） ----------
# 为保证补丁位置正确，每组进入目录 apply
log "Apply kernel bbr3 patches"
pushd target/linux/generic/backport-6.6
bbr3_patches=(
    "010-0001-net-tcp_bbr-broaden-app-limited-rate-sample-detectio.patch"
    "010-0002-net-tcp_bbr-v2-shrink-delivered_mstamp-first_tx_msta.patch"
    "010-0003-net-tcp_bbr-v2-snapshot-packets-in-flight-at-transmi.patch"
    "010-0004-net-tcp_bbr-v2-count-packets-lost-over-TCP-rate-samp.patch"
    "010-0005-net-tcp_bbr-v2-export-FLAG_ECE-in-rate_sample.is_ece.patch"
    "010-0006-net-tcp_bbr-v2-introduce-ca_ops-skb_marked_lost-CC-m.patch"
    "010-0007-net-tcp_bbr-v2-adjust-skb-tx.in_flight-upon-merge-in.patch"
    "010-0008-net-tcp_bbr-v2-adjust-skb-tx.in_flight-upon-split-in.patch"
    "010-0009-net-tcp-add-new-ca-opts-flag-TCP_CONG_WANTS_CE_EVENT.patch"
    "010-0010-net-tcp-re-generalize-TSO-sizing-in-TCP-CC-module-AP.patch"
    "010-0011-net-tcp-add-fast_ack-mode-1-skip-rwin-check-in-tcp_f.patch"
    "010-0012-net-tcp_bbr-v2-record-app-limited-status-of-TLP-repa.patch"
    "010-0013-net-tcp_bbr-v2-inform-CC-module-of-losses-repaired-b.patch"
    "010-0014-net-tcp_bbr-v2-introduce-is_acking_tlp_retrans_seq-i.patch"
    "010-0015-tcp-introduce-per-route-feature-RTAX_FEATURE_ECN_LOW.patch"
    "010-0016-net-tcp_bbr-v3-update-TCP-bbr-congestion-control-mod.patch"
    "010-0017-net-tcp_bbr-v3-ensure-ECN-enabled-BBR-flows-set-ECT-.patch"
    "010-0018-tcp-export-TCPI_OPT_ECN_LOW-in-tcp_info-tcpi_options.patch"
)
for patch in "${bbr3_patches[@]}"; do
    download "$MIRROR/doc/patch/kernel-6.6/bbr3/$patch" "$patch"
    apply_patch "$patch"
done
popd
log "Apply lrng patches"
pushd target/linux/generic/hack-6.6
lrng_patches=(
    "696-01-v57-0001-LRNG-Entropy-Source-and-DRNG-Manager.patch"
    "696-02-v57-0002-LRNG-allocate-one-DRNG-instance-per-NUMA-node.patch"
    "696-03-v57-0003-LRNG-proc-interface.patch"
    "696-04-v57-0004-LRNG-add-switchable-DRNG-support.patch"
    "696-05-v57-0005-LRNG-add-common-generic-hash-support.patch"
    "696-06-v57-0006-crypto-DRBG-externalize-DRBG-functions-for-LRNG.patch"
    "696-07-v57-0007-LRNG-add-SP800-90A-DRBG-extension.patch"
    "696-08-v57-0008-LRNG-add-kernel-crypto-API-PRNG-extension.patch"
    "696-09-v57-0009-LRNG-add-atomic-DRNG-implementation.patch"
    "696-10-v57-0010-LRNG-add-common-timer-based-entropy-source-code.patch"
    "696-11-v57-0011-LRNG-add-interrupt-entropy-source.patch"
    "696-12-v57-0012-scheduler-add-entropy-sampling-hook.patch"
    "696-13-v57-0013-LRNG-add-scheduler-based-entropy-source.patch"
    "696-14-v57-0014-LRNG-add-SP800-90B-compliant-health-tests.patch"
    "696-15-v57-0015-LRNG-add-random.c-entropy-source-support.patch"
    "696-16-v57-0016-LRNG-CPU-entropy-source.patch"
    "696-17-v57-0017-LRNG-add-Jitter-RNG-fast-noise-source.patch"
    "696-18-v57-0018-LRNG-add-option-to-enable-runtime-entropy-rate-c.patch"
    "696-19-v57-0019-LRNG-add-interface-for-gathering-of-raw-entropy.patch"
    "696-20-v57-0020-LRNG-add-power-on-and-runtime-self-tests.patch"
    "696-21-v57-0021-LRNG-sysctls-and-proc-interface.patch"
    "696-22-v57-0022-LRNG-add-drop-in-replacement-random-4-API.patch"
    "696-23-v57-0023-LRNG-add-kernel-crypto-API-interface.patch"
    "696-24-v57-0024-LRNG-add-dev-lrng-device-file-support.patch"
    "696-25-v57-0025-LRNG-add-hwrand-framework-interface.patch"
    "696-26-v57-01-config_base_small.patch"
    "696-27-v57-02-sysctl-unconstify.patch"
)
for patch in "${lrng_patches[@]}"; do
    download "$MIRROR/doc/patch/kernel-6.6/lrng/$patch" "$patch"
    apply_patch "$patch"
done
popd
log "Apply firewall4 patches"
pushd package/network/config/firewall4/patches
fw4_patches=(
    "001-fix-fw4-flow-offload.patch"
    "100-fw4-add-custom-nft-command-support.patch"
    "990-unconditionally-allow-ct-status-dnat.patch"
    "999-01-firewall4-add-fullcone-support.patch"
    "999-02-firewall4-add-bcm-fullconenat-support.patch"
)
for patch in "${fw4_patches[@]}"; do
    download "$MIRROR/doc/patch/firewall4/firewall4_patches/$patch" "$patch"
done
popd
log "Apply libnftnl patches"
pushd package/libs/libnftnl/patches
libnftnl_patches=(
    "0001-libnftnl-add-fullcone-expression-support.patch"
    "0002-libnftnl-add-brcm-fullcone-support.patch"
)
for patch in "${libnftnl_patches[@]}"; do
    download "$MIRROR/doc/patch/firewall4/libnftnl/$patch" "$patch"
done
popd
log "Apply nftables patches"
pushd package/network/utils/nftables/patches
nftables_patches=(
    "0001-nftables-add-fullcone-expression-support.patch"
    "0002-nftables-add-brcm-fullconenat-support.patch"
    "0003-drop-rej-file.patch"
    "100-openwrt-firewall4-add-custom-nft-command-support.patch"
)
for patch in "${nftables_patches[@]}"; do
    download "$MIRROR/doc/patch/firewall4/nftables/$patch" "$patch"
done
popd
log "Apply luci-24.10 firewall patches"
pushd feeds/luci
luci2410_patches=(
    "0001-luci-app-firewall-add-nft-fullcone-and-bcm-fullcone-.patch"
    "0002-luci-app-firewall-add-shortcut-fe-option.patch"
    "0003-luci-app-firewall-add-ipv6-nat-option.patch"
    "0004-luci-add-firewall-add-custom-nft-rule-support.patch"
    "0005-luci-app-firewall-add-natflow-offload-support.patch"
    "0006-luci-app-firewall-enable-hardware-offload-only-on-de.patch"
    "0007-luci-app-firewall-add-fullcone6-option-for-nftables-.patch"
)
for patch in "${luci2410_patches[@]}"; do
    download "$MIRROR/doc/patch/firewall4/luci-24.10/$patch" "$patch"
    apply_patch "$patch"
done
popd
log_end
# ---------- 10️⃣ 旧脚本所有增补包与rootfs美化 ----------
log "Clone extra custom packages (补全部分)"
declare -A EXTRA_PKGS=(
  [nft-fullcone]="https://${GITEA}/nft-fullcone"
  [nat6]="https://${GITHUB}/sbwml/packages_new_nat6"
  [natflow]="https://${GITHUB}/sbwml/package_new_natflow"
  [shortcut-fe]="https://${GITEA}/shortcut-fe"
  [caddy]="https://${GITEA}/luci-app-caddy"
  [mosdns]="https://${GITHUB}/sbwml/luci-app-mosdns"
  [OpenAppFilter]="https://${GITHUB}/destan19/OpenAppFilter"
  [luci-app-poweroffdevice]="https://${GITHUB}/sirpdboy/luci-app-poweroffdevice"
  [frp]="https://${GITHUB}/sbwml/openwrt_frp"
  [ariang-nginx]="https://${GITHUB}/sbwml/ariang-nginx"
  [dockerman]="https://github.com/sirpdboy/luci-app-dockerman.git"
  [samba4]="https://${GITHUB}/sbwml/feeds_packages_net_samba4"
  [quickfile]="https://${GITHUB}/sbwml/luci-app-quickfile"
  [taskplan]="https://github.com/sirpdboy/luci-app-taskplan"
  [adguardhome]="https://${GITEA}/luci-app-adguardhome"
  [poweroff]="https://github.com/sirpdboy/luci-app-poweroffdevice"
)
declare -A EXTRA_BRANCHES=(
  [mosdns]="v5"
  [samba4]=""
)
for pkg in "${!EXTRA_PKGS[@]}"; do
  repo="${EXTRA_PKGS[$pkg]}"
  branch="${EXTRA_BRANCHES[$pkg]:-}" 
  case $pkg in
    dockerman)
      clone_pkg "$repo" "package/new/dockerman" ""
      mv -n package/new/dockerman/luci-app-dockerman feeds/luci/applications/ && rm -rf package/new/dockerman
      ;;
    samba4)
      rm -rf feeds/packages/net/samba4
      clone_pkg "$repo" "feeds/packages/net/samba4" ""
      ;;
    *)
      clone_pkg "$repo" "package/new/$pkg" "$branch" &
      ;;
  esac
done
wait
log_end
# ---------- 11️⃣ IP, root 密码等 --------------------
log "Set default LAN address & root password"
sed -i "s/192.168.1.1/${LAN}/" package/base-files/files/bin/config_generate
if [[ -n "${ROOT_PASSWORD:-}" ]]; then
  pass_hash=$(openssl passwd -5 "${ROOT_PASSWORD}")
  sed -i "s|^root:[^:]*:|root:${pass_hash}:|" package/base-files/files/etc/shadow
fi
log_end
# ---------- 12️⃣ eBPF支持 ---------------------------
if [[ "${ENABLE_OAF:-false}" == "true" ]]; then
  log "Enable BPF syscall for OpenAppFilter"
  sed -i 's/# CONFIG_BPF_SYSCALL is not set/CONFIG_BPF_SYSCALL=y/' .config
  log_end
fi
# ---------- 13️⃣ Rust 编译参数优化 -------------------
log "Disable rust llvm download"
sed -i 's/--set=llvm\.download-ci-llvm=true/--set=llvm.download-ci-llvm=false/' feeds/packages/lang/rust/Makefile
log_end
# ---------- 14️⃣ 各类 rootfs 和主题/美化配置 ---------
log "Rootfs & 主题/profile/bash/sysctl/menu美化 "
# profile
sed -i 's#\\u@\\h:\\w\\\$#\\[\\e[32;1m\\][\\u@\\h\\[\\e[0m\\] \\[\\033[01;34m\\]\\W\\[\\033[00m\\]\\[\\e[32;1m\\]]\\[\\e[0m\\]\\\$#g' package/base-files/files/etc/profile
sed -ri 's/(export PATH=")[^"]*/\1%PATH%:\/opt\/bin:\/opt\/sbin:\/opt\/usr\/bin:\/opt\/usr\/sbin/' package/base-files/files/etc/profile
sed -i '/PS1/a\export TERM=xterm-color' package/base-files/files/etc/profile
# bash增强
sed -i 's#ash#bash#g' package/base-files/files/etc/passwd
sed -i '\#export ENV=/etc/shinit#a export HISTCONTROL=ignoredups' package/base-files/files/etc/profile
mkdir -p files/root
curl -so files/root/.bash_profile $MIRROR/doc/files/root/.bash_profile
curl -so files/root/.bashrc $MIRROR/doc/files/root/.bashrc
# sysctl
mkdir -p files/etc/sysctl.d
curl -so files/etc/sysctl.d/10-default.conf $MIRROR/doc/files/etc/sysctl.d/10-default.conf
curl -so files/etc/sysctl.d/15-vm-swappiness.conf $MIRROR/doc/files/etc/sysctl.d/15-vm-swappiness.conf
curl -so files/etc/sysctl.d/16-udp-buffer-size.conf $MIRROR/doc/files/etc/sysctl.d/16-udp-buffer-size.conf
# banner
#curl -s $MIRROR/Customize/base-files/banner > package/base-files/files/etc/banner
# ZeroWrt options, author, build信息
mkdir -p files/bin
curl -so files/root/version.txt $MIRROR/doc/files/root/version.txt
curl -so files/bin/ZeroWrt $MIRROR/doc/files/bin/ZeroWrt
chmod +x files/bin/ZeroWrt
chmod 644 files/root/version.txt
# author info
sed -i "s/DISTRIB_DESCRIPTION='*.*'/DISTRIB_DESCRIPTION='OpenWrt-$(date +%Y%m%d)'/g"  package/base-files/files/etc/openwrt_release
sed -i "s/DISTRIB_REVISION='*.*'/DISTRIB_REVISION=' By grandway2025'/g" package/base-files/files/etc/openwrt_release
sed -i "s|^OPENWRT_RELEASE=\".*\"|OPENWRT_RELEASE=\"OpenWrt定制版 @R$(date +%Y%m%d) BY grandway2025\"|" package/base-files/files/usr/lib/os-release
sed -i "/BUILD_DATE/d" package/base-files/files/usr/lib/os-release
sed -i "/BUILD_ID/aBUILD_DATE=\"$(date "+%Y-%m-%d")\"" package/base-files/files/usr/lib/os-release
# NTP
sed -i 's/0.openwrt.pool.ntp.org/ntp1.aliyun.com/g' package/base-files/files/bin/config_generate
sed -i 's/1.openwrt.pool.ntp.org/ntp2.aliyun.com/g' package/base-files/files/bin/config_generate
sed -i 's/2.openwrt.pool.ntp.org/time1.cloud.tencent.com/g' package/base-files/files/bin/config_generate
sed -i 's/3.openwrt.pool.ntp.org/time2.cloud.tencent.com/g' package/base-files/files/bin/config_generate
# key
curl -so files/root/key-build.pub https://opkg.kejizero.online/key-build.pub; chmod 644 files/root/key-build.pub
# distfeeds.conf
mkdir -p files/etc/opkg
cat > files/etc/opkg/distfeeds.conf <<EOF
src/gz openwrt_base https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/24.10.2/packages/x86_64/base
src/gz openwrt_luci https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/24.10.2/packages/x86_64/luci
src/gz openwrt_packages https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/24.10.2/packages/x86_64/packages
src/gz openwrt_routing https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/24.10.2/packages/x86_64/routing
src/gz openwrt_telephony https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/24.10.2/packages/x86_64/telephony
EOF
log_end
# ---------- 15️⃣ UI调整UPnP/TTYD/menu order定制 ---------
log "美化 luci 菜单/TTYD/UPnP"
# TTYD
sed -i 's/services/system/g' feeds/luci/applications/luci-app-ttyd/root/usr/share/luci/menu.d/luci-app-ttyd.json
sed -i '3 a\\t\t"order": 50,' feeds/luci/applications/luci-app-ttyd/root/usr/share/luci/menu.d/luci-app-ttyd.json
sed -i 's/procd_set_param stdout 1/procd_set_param stdout 0/g' feeds/packages/utils/ttyd/files/ttyd.init
sed -i 's/procd_set_param stderr 1/procd_set_param stderr 0/g' feeds/packages/utils/ttyd/files/ttyd.init
# UPnP
rm -rf feeds/packages/net/miniupnpd feeds/luci/applications/luci-app-upnp
git clone https://${GITEA}/miniupnpd feeds/packages/net/miniupnpd -b v2.3.9 --depth=1
git clone https://${GITEA}/luci-app-upnp feeds/luci/applications/luci-app-upnp -b openwrt-24.10 --depth=1
# luci menu reorder: nlbwmon
sed -i 's/services/network/g' feeds/luci/applications/luci-app-nlbwmon/root/usr/share/luci/menu.d/luci-app-nlbwmon.json
sed -i 's/services/network/g' feeds/luci/applications/luci-app-nlbwmon/htdocs/luci-static/resources/view/nlbw/config.js
log_end
# ---------- 16️⃣ other定制（如 rootfs bin, ZeroWrt启动脚本, etc/rc.local 等） -----------
cat > ./package/base-files/files/etc/rc.local <<EOF
#!/bin/sh
if ! grep "Default string" /tmp/sysinfo/model > /dev/null; then
    echo should be fine
else
    echo "Generic PC" > /tmp/sysinfo/model
fi
status=\$(cat /sys/devices/system/cpu/intel_pstate/status)
if [ "\$status" = "passive" ]; then
    echo "active" | tee /sys/devices/system/cpu/intel_pstate/status
fi
exit 0
EOF
# ---------- 17️⃣ make defconfig ----------
log "Run make defconfig"
make defconfig
log_end
# ---------- 18️⃣ 输出关键变量至 workflow ----------
DEVICE_TARGET=$(grep ^CONFIG_TARGET_BOARD .config | cut -d'"' -f2)
DEVICE_SUBTARGET=$(grep ^CONFIG_TARGET_SUBTARGET .config | cut -d'"' -f2)
cat <<EOF >> "$GITHUB_ENV"
DEVICE_TARGET=$DEVICE_TARGET
DEVICE_SUBTARGET=$DEVICE_SUBTARGET
EOF
log "DIY script finished ✅"
exit 0
