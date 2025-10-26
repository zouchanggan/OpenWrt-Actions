#!/bin/bash
# =====================
# 配置参数
# =====================
# 脚本URL
export mirror=https://raw.githubusercontent.com/zouchanggan/OpenWrt-Actions/main

# GitHub镜像
export github="github.com"

# 下载进度条
# CURL_BAR="--progress-bar"

# 使用 O2 级别的优化
sed -i 's/Os/O2/g' include/target.mk

# 内核版本设置
curl -s $mirror/doc/kernel-6.6 > include/kernel-6.6
curl -s $mirror/doc/patch/kernel-6.6/kernel/0001-linux-module-video.patch > package/0001-linux-module-video.patch
git apply package/0001-linux-module-video.patch
rm -rf package/0001-linux-module-video.patch

# kenrel Vermagic
sed -ie 's/^\(.\).*vermagic$/\1cp $(TOPDIR)\/.vermagic $(LINUX_DIR)\/.vermagic/' include/kernel-defaults.mk
grep HASH include/kernel-6.6 | awk -F'HASH-' '{print $2}' | awk '{print $1}' | md5sum | awk '{print $1}' > .vermagic

# docker
[ "$ENABLE_DOCKER" = "y" ] && curl -s $mirror/configs/config-docker >> .config

# ShadowSocksR Plus
[ "$ENABLE_SSRP" = "y" ] && curl -s $mirror/configs/config-ssrp >> .config

# passwall
[ "$ENABLE_PASSWALL" = "y" ] && curl -s $mirror/configs/config-passwall >> .config

# nikki
[ "$ENABLE_NIKKI" = "y" ] && curl -s $mirror/configs/config-nikki >> .config

# openclash
[ "$ENABLE_OPENCLASH" = "y" ] && curl -s $mirror/configs/config-openclash >> .config

# Lucky
[ "$ENABLE_LUCKY" = "y" ] && curl -s $mirror/configs/config-lucky >> .config

# AdGuard Home
# [ "$ENABLE_ADGUARDHOME" = "y" ] && curl -s $mirror/configs/config-adguardhome >> .config

# OpenAppFilter
[ "$ENABLE_OAF" = "y" ] && curl -s $mirror/configs/config-oaf >> .config

# 移除 SNAPSHOT 标签
sed -i 's,-SNAPSHOT,,g' include/version.mk
sed -i 's,-SNAPSHOT,,g' package/base-files/image-config.in
sed -i '/CONFIG_BUILDBOT/d' include/feeds.mk
sed -i 's/;)\s*\\/; \\/' include/feeds.mk

# nginx - latest version
rm -rf feeds/packages/net/nginx
git clone https://$github//sbwml/feeds_packages_net_nginx -b openwrt-24.10 feeds/packages/net/nginx
sed -i 's/procd_set_param stdout 1/procd_set_param stdout 0/g;s/procd_set_param stderr 1/procd_set_param stderr 0/g' feeds/packages/net/nginx/files/nginx.init

# nginx - ubus
sed -i 's/ubus_parallel_req 2/ubus_parallel_req 6/g' feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support
sed -i '/ubus_parallel_req/a\        ubus_script_timeout 300;' feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support

# nginx - config
curl -s $mirror/Customize/nginx/luci.locations > feeds/packages/net/nginx/files-luci-support/luci.locations
curl -s $mirror/Customize/nginx/uci.conf.template > feeds/packages/net/nginx-util/files/uci.conf.template

# uwsgi - fix timeout
sed -i '$a cgi-timeout = 600' feeds/packages/net/uwsgi/files-luci-support/luci-*.ini
sed -i '/limit-as/c\limit-as = 5000' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
# disable error log
sed -i "s/procd_set_param stderr 1/procd_set_param stderr 0/g" feeds/packages/net/uwsgi/files/uwsgi.init

# uwsgi - performance
sed -i 's/threads = 1/threads = 2/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i 's/processes = 3/processes = 4/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i 's/cheaper = 1/cheaper = 2/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini

# rpcd - fix timeout
sed -i 's/option timeout 30/option timeout 60/g' package/system/rpcd/files/rpcd.config
sed -i 's#20) \* 1000#60) \* 1000#g' feeds/luci/modules/luci-base/htdocs/luci-static/resources/rpc.js

# 修改默认ip
sed -i "s/192.168.1.1/$LAN/g" package/base-files/files/bin/config_generate

# 为默认 root 密码进行设置
if [ -n "$ROOT_PASSWORD" ]; then
    # sha256 encryption
    default_password=$(openssl passwd -5 $ROOT_PASSWORD)
    sed -i "s|^root:[^:]*:|root:${default_password}:|" package/base-files/files/etc/shadow
fi

# 选择OpenAppFilter开启eBPF 支持
if [ "$ENABLE_OAF" = "y" ]; then
  echo "Enabling eBPF support for OpenAppFilter..."
  sed -i 's/# CONFIG_BPF_SYSCALL is not set/CONFIG_BPF_SYSCALL=y/' .config
fi

# fix_rust_compile_error &&S et Rust build arg llvm.download-ci-llvm to false.
sed -i 's/--set=llvm\.download-ci-llvm=true/--set=llvm.download-ci-llvm=false/' feeds/packages/lang/rust/Makefile

# make olddefconfig
curl -sL $mirror/doc/patch/kernel-6.6/kernel/0003-include-kernel-defaults.mk.patch | patch -p1

# bbr
pushd target/linux/generic/backport-6.6
    curl -Os $mirror/doc/patch/kernel-6.6/bbr3/010-0001-net-tcp_bbr-broaden-app-limited-rate-sample-detectio.patch
    curl -Os $mirror/doc/patch/kernel-6.6/bbr3/010-0002-net-tcp_bbr-v2-shrink-delivered_mstamp-first_tx_msta.patch
    curl -Os $mirror/doc/patch/kernel-6.6/bbr3/010-0003-net-tcp_bbr-v2-snapshot-packets-in-flight-at-transmi.patch
    curl -Os $mirror/doc/patch/kernel-6.6/bbr3/010-0004-net-tcp_bbr-v2-count-packets-lost-over-TCP-rate-samp.patch
    curl -Os $mirror/doc/patch/kernel-6.6/bbr3/010-0005-net-tcp_bbr-v2-export-FLAG_ECE-in-rate_sample.is_ece.patch
    curl -Os $mirror/doc/patch/kernel-6.6/bbr3/010-0006-net-tcp_bbr-v2-introduce-ca_ops-skb_marked_lost-CC-m.patch
    curl -Os $mirror/doc/patch/kernel-6.6/bbr3/010-0007-net-tcp_bbr-v2-adjust-skb-tx.in_flight-upon-merge-in.patch
    curl -Os $mirror/doc/patch/kernel-6.6/bbr3/010-0008-net-tcp_bbr-v2-adjust-skb-tx.in_flight-upon-split-in.patch
    curl -Os $mirror/doc/patch/kernel-6.6/bbr3/010-0009-net-tcp-add-new-ca-opts-flag-TCP_CONG_WANTS_CE_EVENT.patch
    curl -Os $mirror/doc/patch/kernel-6.6/bbr3/010-0010-net-tcp-re-generalize-TSO-sizing-in-TCP-CC-module-AP.patch
    curl -Os $mirror/doc/patch/kernel-6.6/bbr3/010-0011-net-tcp-add-fast_ack_mode-1-skip-rwin-check-in-tcp_f.patch
    curl -Os $mirror/doc/patch/kernel-6.6/bbr3/010-0012-net-tcp_bbr-v2-record-app-limited-status-of-TLP-repa.patch
    curl -Os $mirror/doc/patch/kernel-6.6/bbr3/010-0013-net-tcp_bbr-v2-inform-CC-module-of-losses-repaired-b.patch
    curl -Os $mirror/doc/patch/kernel-6.6/bbr3/010-0014-net-tcp_bbr-v2-introduce-is_acking_tlp_retrans_seq-i.patch
    curl -Os $mirror/doc/patch/kernel-6.6/bbr3/010-0015-tcp-introduce-per-route-feature-RTAX_FEATURE_ECN_LOW.patch
    curl -Os $mirror/doc/patch/kernel-6.6/bbr3/010-0016-net-tcp_bbr-v3-update-TCP-bbr-congestion-control-mod.patch
    curl -Os $mirror/doc/patch/kernel-6.6/bbr3/010-0017-net-tcp_bbr-v3-ensure-ECN-enabled-BBR-flows-set-ECT-.patch
    curl -Os $mirror/doc/patch/kernel-6.6/bbr3/010-0018-tcp-export-TCPI_OPT_ECN_LOW-in-tcp_info-tcpi_options.patch
popd

# LRNG
echo '
# CONFIG_RANDOM_DEFAULT_IMPL is not set
CONFIG_LRNG=y
CONFIG_LRNG_DEV_IF=y
# CONFIG_LRNG_IRQ is not set
CONFIG_LRNG_JENT=y
CONFIG_LRNG_CPU=y
# CONFIG_LRNG_SCHED is not set
CONFIG_LRNG_SELFTEST=y
# CONFIG_LRNG_SELFTEST_PANIC is not set
' >>./target/linux/generic/config-6.6
pushd target/linux/generic/hack-6.6
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-01-v57-0001-LRNG-Entropy-Source-and-DRNG-Manager.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-02-v57-0002-LRNG-allocate-one-DRNG-instance-per-NUMA-node.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-03-v57-0003-LRNG-proc-interface.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-04-v57-0004-LRNG-add-switchable-DRNG-support.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-05-v57-0005-LRNG-add-common-generic-hash-support.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-06-v57-0006-crypto-DRBG-externalize-DRBG-functions-for-LRNG.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-07-v57-0007-LRNG-add-SP800-90A-DRBG-extension.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-08-v57-0008-LRNG-add-kernel-crypto-API-PRNG-extension.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-09-v57-0009-LRNG-add-atomic-DRNG-implementation.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-10-v57-0010-LRNG-add-common-timer-based-entropy-source-code.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-11-v57-0011-LRNG-add-interrupt-entropy-source.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-12-v57-0012-scheduler-add-entropy-sampling-hook.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-13-v57-0013-LRNG-add-scheduler-based-entropy-source.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-14-v57-0014-LRNG-add-SP800-90B-compliant-health-tests.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-15-v57-0015-LRNG-add-random.c-entropy-source-support.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-16-v57-0016-LRNG-CPU-entropy-source.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-17-v57-0017-LRNG-add-Jitter-RNG-fast-noise-source.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-18-v57-0018-LRNG-add-option-to-enable-runtime-entropy-rate-c.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-19-v57-0019-LRNG-add-interface-for-gathering-of-raw-entropy.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-20-v57-0020-LRNG-add-power-on-and-runtime-self-tests.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-21-v57-0021-LRNG-sysctls-and-proc-interface.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-22-v57-0022-LRMG-add-drop-in-replacement-random-4-API.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-23-v57-0023-LRNG-add-kernel-crypto-API-interface.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-24-v57-0024-LRNG-add-dev-lrng-device-file-support.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-25-v57-0025-LRNG-add-hwrand-framework-interface.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-26-v57-01-config_base_small.patch
    curl -Os $mirror/doc/patch/kernel-6.6/lrng/696-27-v57-02-sysctl-unconstify.patch
popd

# firewall4
mkdir -p package/network/config/firewall4/patches
curl -s $mirror/Customize/firewall4/Makefile > package/network/config/firewall4/Makefile
sed -i 's|$(PROJECT_GIT)/project|https://github.com/openwrt|g' package/network/config/firewall4/Makefile

# fix ct status dnat
curl -s $mirror/doc/patch/firewall4/firewall4_patches/990-unconditionally-allow-ct-status-dnat.patch > package/network/config/firewall4/patches/990-unconditionally-allow-ct-status-dnat.patch

# fullcone
curl -s $mirror/doc/patch/firewall4/firewall4_patches/999-01-firewall4-add-fullcone-support.patch > package/network/config/firewall4/patches/999-01-firewall4-add-fullcone-support.patch

# bcm fullcone
curl -s $mirror/doc/patch/firewall4/firewall4_patches/999-02-firewall4-add-bcm-fullconenat-support.patch > package/network/config/firewall4/patches/999-02-firewall4-add-bcm-fullconenat-support.patch

# fix flow offload
curl -s $mirror/doc/patch/firewall4/firewall4_patches/001-fix-fw4-flow-offload.patch > package/network/config/firewall4/patches/001-fix-fw4-flow-offload.patch

# add custom nft command support
curl -s $mirror/doc/patch/firewall4/100-openwrt-firewall4-add-custom-nft-command-support.patch | patch -p1

# libnftnl
mkdir -p package/libs/libnftnl/patches
curl -s $mirror/doc/patch/firewall4/libnftnl/0001-libnftnl-add-fullcone-expression-support.patch > package/libs/libnftnl/patches/0001-libnftnl-add-fullcone-expression-support.patch
curl -s $mirror/doc/patch/firewall4/libnftnl/0002-libnftnl-add-brcm-fullcone-support.patch > package/libs/libnftnl/patches/0002-libnftnl-add-brcm-fullcone-support.patch

# kernel patch
# btf: silence btf module warning messages
curl -s $mirror/doc/patch/kernel-6.6/btf/990-btf-silence-btf-module-warning-messages.patch > target/linux/generic/hack-6.6/990-btf-silence-btf-module-warning-messages.patch
# cpu model
curl -s $mirror/doc/patch/kernel-6.6/arm64/312-arm64-cpuinfo-Add-model-name-in-proc-cpuinfo-for-64bit-ta.patch > target/linux/generic/hack-6.6/312-arm64-cpuinfo-Add-model-name-in-proc-cpuinfo-for-64bit-ta.patch
# fullcone
curl -s $mirror/doc/patch/kernel-6.6/net/952-net-conntrack-events-support-multiple-registrant.patch > target/linux/generic/hack-6.6/952-net-conntrack-events-support-multiple-registrant.patch
# bcm-fullcone
curl -s $mirror/doc/patch/kernel-6.6/net/982-add-bcm-fullcone-support.patch > target/linux/generic/hack-6.6/982-add-bcm-fullcone-support.patch
curl -s $mirror/doc/patch/kernel-6.6/net/983-add-bcm-fullcone-nft_masq-support.patch > target/linux/generic/hack-6.6/983-add-bcm-fullcone-nft_masq-support.patch
# shortcut-fe
curl -s $mirror/doc/patch/kernel-6.6/net/601-netfilter-export-udp_get_timeouts-function.patch > target/linux/generic/hack-6.6/601-netfilter-export-udp_get_timeouts-function.patch
curl -s $mirror/doc/patch/kernel-6.6/net/953-net-patch-linux-kernel-to-support-shortcut-fe.patch > target/linux/generic/hack-6.6/953-net-patch-linux-kernel-to-support-shortcut-fe.patch

# nftables
mkdir -p package/network/utils/nftables/patches
curl -s $mirror/doc/patch/firewall4/nftables/0001-nftables-add-fullcone-expression-support.patch > package/network/utils/nftables/patches/0001-nftables-add-fullcone-expression-support.patch
curl -s $mirror/doc/patch/firewall4/nftables/0002-nftables-add-brcm-fullconenat-support.patch > package/network/utils/nftables/patches/0002-nftables-add-brcm-fullconenat-support.patch
curl -s $mirror/doc/patch/firewall4/nftables/0003-drop-rej-file.patch > package/network/utils/nftables/patches/0003-drop-rej-file.patch

# FullCone module
git clone https://$github/grandway2025/nft-fullcone package/new/nft-fullcone

# IPv6 NAT
git clone https://$github/grandway2025/package_new_nat6 package/new/nat6

# natflow
git clone https://$github/grandway2025/package_new_natflow package/new/natflow

# sfe
git clone https://$github/grandway2025/shortcut-fe package/new/shortcut-fe

# Patch Luci add nft_fullcone/bcm_fullcone & shortcut-fe & natflow & ipv6-nat & custom nft command option
pushd feeds/luci
    curl -s $mirror/doc/patch/firewall4/luci-24.10/0001-luci-app-firewall-add-nft-fullcone-and-bcm-fullcone-.patch | patch -p1
    curl -s $mirror/doc/patch/firewall4/luci-24.10/0002-luci-app-firewall-add-shortcut-fe-option.patch | patch -p1
    curl -s $mirror/doc/patch/firewall4/luci-24.10/0003-luci-app-firewall-add-ipv6-nat-option.patch | patch -p1
    curl -s $mirror/doc/patch/firewall4/luci-24.10/0004-luci-add-firewall-add-custom-nft-rule-support.patch | patch -p1
    curl -s $mirror/doc/patch/firewall4/luci-24.10/0005-luci-app-firewall-add-natflow-offload-support.patch | patch -p1
    curl -s $mirror/doc/patch/firewall4/luci-24.10/0006-luci-app-firewall-enable-hardware-offload-only-on-de.patch | patch -p1
    curl -s $mirror/doc/patch/firewall4/luci-24.10/0007-luci-app-firewall-add-fullcone6-option-for-nftables-.patch | patch -p1
popd

# luci-mod extra
pushd feeds/luci
    curl -s $mirror/doc/patch/luci/0001-luci-mod-system-add-modal-overlay-dialog-to-reboot.patch | patch -p1
    curl -s $mirror/doc/patch/luci/0002-luci-mod-status-displays-actual-process-memory-usage.patch | patch -p1
    curl -s $mirror/doc/patch/luci/0003-luci-mod-status-storage-index-applicable-only-to-val.patch | patch -p1
    curl -s $mirror/doc/patch/luci/0004-luci-mod-status-firewall-disable-legacy-firewall-rul.patch | patch -p1
    curl -s $mirror/doc/patch/luci/0005-luci-mod-system-add-refresh-interval-setting.patch | patch -p1
    curl -s $mirror/doc/patch/luci/0006-luci-mod-system-mounts-add-docker-directory-mount-po.patch | patch -p1
    curl -s $mirror/doc/patch/luci/0007-luci-mod-system-add-ucitrack-luci-mod-system-zram.js.patch | patch -p1
popd

# igc-fix
curl -s $mirror/doc/patch/kernel-6.6/igc-fix/996-intel-igc-i225-i226-disable-eee.patch > target/linux/x86/patches-6.6/996-intel-igc-i225-i226-disable-eee.patch

# Docker
rm -rf feeds/luci/applications/luci-app-dockerman
git clone https://github.com/sirpdboy/luci-app-dockerman.git package/new/dockerman
mv -n package/new/dockerman/luci-app-dockerman feeds/luci/applications && rm -rf package/new/dockerman
rm -rf feeds/packages/utils/{docker,dockerd,containerd,runc}
git clone https://$github/sbwml/packages_utils_docker feeds/packages/utils/docker
git clone https://$github/sbwml/packages_utils_dockerd feeds/packages/utils/dockerd
git clone https://$github/sbwml/packages_utils_containerd feeds/packages/utils/containerd
git clone https://$github/sbwml/packages_utils_runc feeds/packages/utils/runc

# TTYD
sed -i 's/services/system/g' feeds/luci/applications/luci-app-ttyd/root/usr/share/luci/menu.d/luci-app-ttyd.json
sed -i '3 a\\t\t"order": 50,' feeds/luci/applications/luci-app-ttyd/root/usr/share/luci/menu.d/luci-app-ttyd.json
sed -i 's/procd_set_param stdout 1/procd_set_param stdout 0/g' feeds/packages/utils/ttyd/files/ttyd.init
sed -i 's/procd_set_param stderr 1/procd_set_param stderr 0/g' feeds/packages/utils/ttyd/files/ttyd.init

# UPnP
# rm -rf feeds/{packages/net/miniupnpd,luci/applications/luci-app-upnp}
# git clone https://$github/grandway2025/miniupnpd feeds/packages/net/miniupnpd
# git clone https://$github/grandway2025/luci-app-upnp feeds/luci/applications/luci-app-upnp

# profile
sed -i 's#\\u@\\h:\\w\\\$#\\[\\e[32;1m\\][\\u@\\h\\[\\e[0m\\] \\[\\033[01;34m\\]\\W\\[\\033[00m\\]\\[\\e[32;1m\\]]\\[\\e[0m\\]\\\$#g' package/base-files/files/etc/profile
sed -ri 's/(export PATH=")[^"]*/\1%PATH%:\/opt\/bin:\/opt\/sbin:\/opt\/usr\/bin:\/opt\/usr\/sbin/' package/base-files/files/etc/profile
sed -i '/ENV/i\export TERM=xterm-color' package/base-files/files/etc/profile

# 切换bash
sed -i 's#ash#bash#g' package/base-files/files/etc/passwd
sed -i '\#export ENV=/etc/shinit#a export HISTCONTROL=ignoredups' package/base-files/files/etc/profile
mkdir -p files/root
curl -so files/root/.bash_profile $mirror/doc/files/root/.bash_profile
curl -so files/root/.bashrc $mirror/doc/files/root/.bashrc

# rootfs files
mkdir -p files/etc/sysctl.d
mkdir -p files/etc/hotplug.d/iface
mkdir -p files/etc/hotplug.d/net
curl -so files/etc/sysctl.d/10-default.conf $mirror/doc/files/etc/sysctl.d/10-default.conf
curl -so files/etc/sysctl.d/15-vm-swappiness.conf $mirror/doc/files/etc/sysctl.d/15-vm-swappiness.conf
curl -so files/etc/sysctl.d/16-udp-buffer-size.conf $mirror/doc/files/etc/sysctl.d/16-udp-buffer-size.conf
curl -so files/etc/hotplug.d/iface/99-zzz-odhcpd $mirror/doc/files/etc/hotplug.d/iface/99-zzz-odhcpd
curl -so files/etc/hotplug.d/net/01-maximize_nic_rx_tx_buffers  $mirror/doc/files/etc/hotplug.d/net/01-maximize_nic_rx_tx_buffers

# ZeroWrt Options Menu
mkdir -p files/bin
curl -so files/root/version.txt $mirror/doc/files/root/version.txt
curl -so files/bin/ZeroWrt $mirror/doc/files/bin/ZeroWrt
chmod +x files/bin/ZeroWrt
chmod +x files/root/version.txt

# key-build.pub
curl -so files/root/key-build.pub https://opkg.kejizero.online/key-build.pub
chmod +x files/root/key-build.pub

# NTP
sed -i 's/0.openwrt.pool.ntp.org/ntp1.aliyun.com/g' package/base-files/files/bin/config_generate
sed -i 's/1.openwrt.pool.ntp.org/ntp2.aliyun.com/g' package/base-files/files/bin/config_generate
sed -i 's/2.openwrt.pool.ntp.org/time1.cloud.tencent.com/g' package/base-files/files/bin/config_generate
sed -i 's/3.openwrt.pool.ntp.org/time2.cloud.tencent.com/g' package/base-files/files/bin/config_generate

# 加入作者信息
sed -i "s/DISTRIB_DESCRIPTION='*.*'/DISTRIB_DESCRIPTION='OpenWrt-$(date +%Y%m%d)'/g"  package/base-files/files/etc/openwrt_release
sed -i "s/DISTRIB_REVISION='*.*'/DISTRIB_REVISION=' By grandway2025'/g" package/base-files/files/etc/openwrt_release
sed -i "s|^OPENWRT_RELEASE=\".*\"|OPENWRT_RELEASE=\"OpenWrt定制版 @R$(date +%Y%m%d) BY grandway2025\"|" package/base-files/files/usr/lib/os-release

# CURRENT_DATE
sed -i "/BUILD_DATE/d" package/base-files/files/usr/lib/os-release
sed -i "/BUILD_ID/aBUILD_DATE=\"$CURRENT_DATE\"" package/base-files/files/usr/lib/os-release

# golang 1.25
rm -rf feeds/packages/lang/golang
git clone https://$github/sbwml/packages_lang_golang -b 25.x feeds/packages/lang/golang

# luci-app-webdav
git clone https://$github/sbwml/luci-app-webdav package/new/luci-app-webdav

# luci-app-quickfile
git clone https://$github/sbwml/luci-app-quickfile package/new/quickfile

# ddns - fix boot
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
curl -s $mirror/Customize/frpc/001-luci-app-frpc-hide-token.patch | patch -p1
curl -s $mirror/Customize/frpc/002-luci-app-frpc-add-enable-flag.patch | patch -p1

# natmap
sed -i 's/log_stdout:bool:1/log_stdout:bool:0/g;s/log_stderr:bool:1/log_stderr:bool:0/g' feeds/packages/net/natmap/files/natmap.init
pushd feeds/luci
    curl -s $mirror/Customize/natmap/0001-luci-app-natmap-add-default-STUN-server-lists.patch | patch -p1
popd

# samba4 - bump version
rm -rf feeds/packages/net/samba4
git clone https://$github/sbwml/feeds_packages_net_samba4 feeds/packages/net/samba4
# liburing - 2.7 (samba-4.21.0)
rm -rf feeds/packages/libs/liburing
git clone https://$github/sbwml/feeds_packages_libs_liburing feeds/packages/libs/liburing
# enable multi-channel
sed -i '/workgroup/a \\n\t## enable multi-channel' feeds/packages/net/samba4/files/smb.conf.template
sed -i '/enable multi-channel/a \\tserver multi channel support = yes' feeds/packages/net/samba4/files/smb.conf.template
# default config
sed -i 's/#aio read size = 0/aio read size = 0/g' feeds/packages/net/samba4/files/smb.conf.template
sed -i 's/#aio write size = 0/aio write size = 0/g' feeds/packages/net/samba4/files/smb.conf.template
sed -i 's/invalid users = root/#invalid users = root/g' feeds/packages/net/samba4/files/smb.conf.template
sed -i 's/bind interfaces only = yes/bind interfaces only = no/g' feeds/packages/net/samba4/files/smb.conf.template
sed -i 's/#create mask/create mask/g' feeds/packages/net/samba4/files/smb.conf.template
sed -i 's/#directory mask/directory mask/g' feeds/packages/net/samba4/files/smb.conf.template
sed -i 's/0666/0644/g;s/0744/0755/g;s/0777/0755/g' feeds/luci/applications/luci-app-samba4/htdocs/luci-static/resources/view/samba4.js
sed -i 's/0666/0644/g;s/0777/0755/g' feeds/packages/net/samba4/files/samba.config
sed -i 's/0666/0644/g;s/0777/0755/g' feeds/packages/net/samba4/files/smb.conf.template

# aria2 & ariaNG
rm -rf feeds/packages/net/ariang
rm -rf feeds/luci/applications/luci-app-aria2
git clone https://$github/sbwml/ariang-nginx package/new/ariang-nginx
rm -rf feeds/packages/net/aria2
git clone https://$github/sbwml/feeds_packages_net_aria2 -b 22.03 feeds/packages/net/aria2

# SSRP & Passwall
rm -rf feeds/packages/net/{xray-core,v2ray-core,v2ray-geodata,sing-box}
git clone https://$github/sbwml/openwrt_helloworld package/new/helloworld -b v5 --depth=1

# openlist
git clone https://$github/sbwml/luci-app-openlist2 package/new/openlist --depth=1

# netdata
sed -i 's/syslog/none/g' feeds/packages/admin/netdata/files/netdata.conf

# caddy
git clone https://$github/grandway2025/luci-app-caddy package/new/caddy

# Mosdns
git clone https://$github/sbwml/luci-app-mosdns -b v5 package/new/mosdns

# OpenAppFilter
git clone https://$github/destan19/OpenAppFilter package/new/OpenAppFilter

# adguardhome
git clone https://$github/grandway2025/luci-app-adguardhome package/new/luci-app-adguardhome

# unzip
rm -rf feeds/packages/utils/unzip
git clone https://$github/sbwml/feeds_packages_utils_unzip feeds/packages/utils/unzip

# PowerOff 关机插件
git clone https://github.com/sirpdboy/luci-app-poweroffdevice package/new/poweroff
mv -n package/new/poweroff/luci-app-poweroffdevice package/new/luci-app-poweroffdevice && rm -rf package/new/poweroff

# luci-app-taskplan
git clone https://github.com/sirpdboy/luci-app-taskplan package/new/luci-app-taskplan

# iperf3
sed -i "s/D_GNU_SOURCE/D_GNU_SOURCE -funroll-loops/g" feeds/packages/net/iperf3/Makefile

# nlbwmon
sed -i 's/services/network/g' feeds/luci/applications/luci-app-nlbwmon/root/usr/share/luci/menu.d/luci-app-nlbwmon.json
sed -i 's/services/network/g' feeds/luci/applications/luci-app-nlbwmon/htdocs/luci-static/resources/view/nlbw/config.js

# argon && argon-config
rm -rf feeds/luci/themes/luci-theme-argon
git clone https://$github/grandway2025/argon package/new/luci-theme-argon --depth=1

# luci-app-advancedplus
git clone https://$github/sirpdboy/luci-app-advancedplus.git package/new/luci-app-advancedplus

# luci-theme-kucat
git clone https://$github/sirpdboy/luci-theme-kucat.git package/new/kucat
mv -n package/new/kucat/luci-theme-kucat package/new/luci-theme-kucat && rm -rf package/new/kucat

# lucky
git clone https://$github/gdy666/luci-app-lucky.git package/new/lucky

# luci-app-socat
git clone https://$github/grandway2025/luci-app-socat package/new/socat
mv -n package/new/socat/luci-app-socat package/new/luci-app-socat && rm -rf package/new/socat

# custom packages pkgs
rm -rf feeds/packages/utils/coremark
git clone https://$github/sbwml/openwrt_pkgs package/new/custom --depth=1
rm -rf package/new/custom/luci-app-adguardhome

# autocore-arm
git clone https://$github/grandway2025/autocore-arm package/new/autocore-arm

sed -i 's/O2/O2 -march=x86-64-v2/g' include/target.mk

# libsodium
sed -i 's,no-mips16 no-lto,no-mips16,g' feeds/packages/libs/libsodium/Makefile

echo '#!/bin/sh
# Put your custom commands here that should be executed once
# the system init finished. By default this file does nothing.

if ! grep "Default string" /tmp/sysinfo/model > /dev/null; then
    echo should be fine
else
    echo "Generic PC" > /tmp/sysinfo/model
fi

status=$(cat /sys/devices/system/cpu/intel_pstate/status)

if [ "$status" = "passive" ]; then
    echo "active" | tee /sys/devices/system/cpu/intel_pstate/status
fi

exit 0
'> ./package/base-files/files/etc/rc.local

# 默认设置
git clone https://$github/grandway2025/default-settings package/new/default-settings -b openwrt-24.10

# distfeeds.conf
mkdir -p files/etc/opkg
cat > files/etc/opkg/distfeeds.conf <<EOF
src/gz openwrt_base https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/24.10.2/packages/x86_64/base
src/gz openwrt_luci https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/24.10.2/packages/x86_64/luci
src/gz openwrt_packages https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/24.10.2/packages/x86_64/packages
src/gz openwrt_routing https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/24.10.2/packages/x86_64/routing
src/gz openwrt_telephony https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/24.10.2/packages/x86_64/telephony
EOF

# fix_rust_compile_error &&S et Rust build arg llvm.download-ci-llvm to false.
sed -i 's/--set=llvm\.download-ci-llvm=true/--set=llvm.download-ci-llvm=false/' feeds/packages/lang/rust/Makefile

# Vermagic
# curl -s https://downloads.openwrt.org/releases/24.10.1/targets/x86/64/openwrt-24.10.1-x86-64.manifest \
# | grep "^kernel -" \
# | awk '{print $3}' \
# | sed -n 's/.*~\([a-f0-9]\+\)-r[0-9]\+/\1/p' > vermagic
# sed -i 's#grep '\''=\[ym\]'\'' \$(LINUX_DIR)/\.config\.set | LC_ALL=C sort | \$(MKHASH) md5 > \$(LINUX_DIR)/\.vermagic#cp \$(TOPDIR)/vermagic \$(LINUX_DIR)/.vermagic#g' include/kernel-defaults.mk

# Toolchain Cache
#if [ "$BUILD_FAST" = "y" ]; then
#    TOOLCHAIN_URL=https://github.com/oppen321/openwrt_caches/releases/download/OpenWrt_Toolchain_Cache
#    curl -L -k ${TOOLCHAIN_URL}/toolchain_gcc13_x86_64.tar.zst -o toolchain.tar.zst $CURL_BAR
#    tar -I "zstd" -xf toolchain.tar.zst
#    rm -f toolchain.tar.zst
#    mkdir bin
#    find ./staging_dir/ -name '*' -exec touch {} \; >/dev/null 2>&1
#    find ./tmp/ -name '*' -exec touch {} \; >/dev/null 2>&1
#fi

# init openwrt config
rm -rf tmp/*
