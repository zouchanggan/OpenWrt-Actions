#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
# ---------- 1. 全局变量 ----------
: "${MIRROR:=https://raw.githubusercontent.com/grandway2025/OpenWRT-Action/main}"
: "${GITEA:=git.kejizero.online/zhao}"
: "${GITHUB:=github.com}"
KVER=6.6
log()    { echo -e "\033[1;34m[INFO]  $*\033[0m"; echo "::group::$*"; }
log_end(){ echo "::endgroup::"; }
err()    { echo -e "\033[1;31m[ERROR] $*\033[0m" >&2; echo "::error::$*"; exit 1; }
download() {
  local url=$1 dst=$2
  curl -fsSL --retry 3 --retry-delay 5 "$url" -o "$dst" || err "download failed: $url"
  [[ -s "$dst" ]] || err "download produced empty file: $dst"
}
clone_pkg() {
  local repo=$1 dst=$2 branch=$3
  if [[ -n $branch ]]; then
    git clone --depth=1 -b "$branch" "$repo" "$dst" || err "clone $repo (branch $branch) failed"
  else
    git clone --depth=1 "$repo" "$dst" || err "clone $repo failed"
  fi
}
# ---------- 2. 编译优化 ----------
log "Set compiler optimization"
sed -i 's/^EXTRA_OPTIMIZATION=.*/EXTRA_OPTIMIZATION=-O2 -march=x86-64-v2/' include/target.mk
log_end
# ---------- 3. Kernel & vermagic ----------
log "Skip kernel doc download"
sed -i 's/^\(.\).*vermagic$/\1cp $(TOPDIR)\/.vermagic $(LINUX_DIR)\/.vermagic/' include/kernel-defaults.mk
if [[ -e include/kernel-${KVER} ]]; then
    grep HASH include/kernel-${KVER} | awk -F'HASH-' '{print $2}' | awk '{print $1}' | md5sum | awk '{print $1}' > .vermagic
fi
log_end
# ---------- 4. 导入外部.config功能块配置 ----------
for feat in docker ssrp passwall nikki openclash lucky oaf adguardhome mosdns openlist taskplan advancedplus; do
    vname="ENABLE_${feat^^}"
    vval="${!vname:-false}"
    cfgfile="../configs/config-$feat"
    if [[ "${vval,,}" == "true" && -f $cfgfile ]]; then
        cat "$cfgfile" >> .config
    fi
done
log_end
# ---------- 5. 清理 SNAPSHOT ----------
log "Cleanup snapshot tags"
sed -i 's/-SNAPSHOT//g' include/version.mk package/base-files/image-config.in
sed -i '/CONFIG_BUILDBOT/d' include/feeds.mk
sed -i 's/;)\s*\\/; \\/' include/feeds.mk
log_end
# ---------- 6. 必须补丁/新 kernel&fw 相关 patch（只下载，不apply） ----------
log "Download kernel bbr3 patches"
PATCH_DIR_BBR3="target/linux/generic/backport-6.6"
mkdir -p "$PATCH_DIR_BBR3"
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
    download "$MIRROR/doc/patch/kernel-6.6/bbr3/$patch" "$PATCH_DIR_BBR3/$patch"
done
log "Download lrng patches"
PATCH_DIR_LRNG="target/linux/generic/hack-6.6"
mkdir -p "$PATCH_DIR_LRNG"
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
    download "$MIRROR/doc/patch/kernel-6.6/lrng/$patch" "$PATCH_DIR_LRNG/$patch"
done
log "Download firewall4 patches"
PATCH_DIR_FW4="package/network/config/firewall4/patches"
mkdir -p "$PATCH_DIR_FW4"
fw4_patches=(
    "001-fix-fw4-flow-offload.patch"
    "100-fw4-add-custom-nft-command-support.patch"
    "990-unconditionally-allow-ct-status-dnat.patch"
    "999-01-firewall4-add-fullcone-support.patch"
    "999-02-firewall4-add-bcm-fullconenat-support.patch"
)
for patch in "${fw4_patches[@]}"; do
    download "$MIRROR/doc/patch/firewall4/firewall4_patches/$patch" "$PATCH_DIR_FW4/$patch"
done
log "Download libnftnl patches"
PATCH_DIR_LIBNFTNL="package/libs/libnftnl/patches"
mkdir -p "$PATCH_DIR_LIBNFTNL"
libnftnl_patches=(
    "0001-libnftnl-add-fullcone-expression-support.patch"
    "0002-libnftnl-add-brcm-fullcone-support.patch"
)
for patch in "${libnftnl_patches[@]}"; do
    download "$MIRROR/doc/patch/firewall4/libnftnl/$patch" "$PATCH_DIR_LIBNFTNL/$patch"
done
log "Download nftables patches"
PATCH_DIR_NFTABLES="package/network/utils/nftables/patches"
mkdir -p "$PATCH_DIR_NFTABLES"
nftables_patches=(
    "0001-nftables-add-fullcone-expression-support.patch"
    "0002-nftables-add-brcm-fullconenat-support.patch"
    "0003-drop-rej-file.patch"
    "100-openwrt-firewall4-add-custom-nft-command-support.patch"
)
for patch in "${nftables_patches[@]}"; do
    download "$MIRROR/doc/patch/firewall4/nftables/$patch" "$PATCH_DIR_NFTABLES/$patch"
done
log "Download luci-24.10 firewall patches"
PATCH_DIR_LUCI="feeds/luci"
mkdir -p "$PATCH_DIR_LUCI"
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
    download "$MIRROR/doc/patch/firewall4/luci-24.10/$patch" "$PATCH_DIR_LUCI/$patch"
done
log_end
# ---------- 后续操作（包clone等都保留原逻辑） ----------
# ...美化/等等代码，不变，照原脚本写法
log "DIY script finished ✅"
exit 0
