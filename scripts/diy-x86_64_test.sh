#!/bin/bash
# ======================================
# DIY 脚本 for x86_64 (OpenWrt)
# 结构现代化，逻辑分区+全注释+无通配符
# ======================================
set -e
# ========== 1. 通用环境变量 ==========
export mirror=https://raw.githubusercontent.com/zouchanggan/OpenWrt-Actions/main
export gitea=git.kejizero.online/zhao
export github="github.com"
# ---------- 2. 编译优化与内核版本处理 ----------
sed -i 's/Os/O2/g' include/target.mk
sed -i 's/O2/O2 -march=x86-64-v2/g' include/target.mk
curl -s $mirror/doc/kernel-6.6 > include/kernel-6.6
curl -s $mirror/doc/patch/kernel-6.6/kernel/0001-linux-module-video.patch > package/0001-linux-module-video.patch
git apply package/0001-linux-module-video.patch
rm -rf package/0001-linux-module-video.patch
sed -ie 's/^\(.\).*vermagic$/\1cp $(TOPDIR)\/.vermagic $(LINUX_DIR)\/.vermagic/' include/kernel-defaults.mk
grep HASH include/kernel-6.6 | awk -F'HASH-' '{print $2}' | awk '{print $1}' | md5sum | awk '{print $1}' > .vermagic
# ---------- 3. 可选功能追加到.config ----------
[ "$ENABLE_DOCKER"     = "y" ] && curl -s $mirror/configs/config-docker     >> .config
[ "$ENABLE_SSRP"       = "y" ] && curl -s $mirror/configs/config-ssrp       >> .config
[ "$ENABLE_PASSWALL"   = "y" ] && curl -s $mirror/configs/config-passwall   >> .config
[ "$ENABLE_NIKKI"      = "y" ] && curl -s $mirror/configs/config-nikki      >> .config
[ "$ENABLE_OPENCLASH"  = "y" ] && curl -s $mirror/configs/config-openclash  >> .config
[ "$ENABLE_LUCKY"      = "y" ] && curl -s $mirror/configs/config-lucky      >> .config
[ "$ENABLE_OAF"        = "y" ] && curl -s $mirror/configs/config-oaf        >> .config
# ---------- 4. 系统版本标签、美化修正 ----------
sed -i 's,-SNAPSHOT,,g' include/version.mk
sed -i 's,-SNAPSHOT,,g' package/base-files/image-config.in
sed -i '/CONFIG_BUILDBOT/d' include/feeds.mk
sed -i 's/;)\s*\\/; \\/' include/feeds.mk
# ---------- 5. nginx、uwsgi、rpcd 性能修正 ----------
rm -rf feeds/packages/net/nginx
git clone https://$github/sbwml/feeds_packages_net_nginx feeds/packages/net/nginx -b openwrt-24.10
sed -i 's/procd_set_param stdout 1/procd_set_param stdout 0/g;s/procd_set_param stderr 1/procd_set_param stderr 0/g' feeds/packages/net/nginx/files/nginx.init
sed -i 's/ubus_parallel_req 2/ubus_parallel_req 6/g' feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support
sed -i '/ubus_parallel_req/a\        ubus_script_timeout 300;' feeds/packages/net/nginx/files-luci-support/60_nginx-luci-support
curl -s $mirror/Customize/nginx/luci.locations > feeds/packages/net/nginx/files-luci-support/luci.locations
curl -s $mirror/Customize/nginx/uci.conf.template > feeds/packages/net/nginx-util/files/uci.conf.template
sed -i '$a cgi-timeout = 600' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i '/limit-as/c\limit-as = 5000' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i 's/procd_set_param stderr 1/procd_set_param stderr 0/g' feeds/packages/net/uwsgi/files/uwsgi.init
sed -i 's/threads = 1/threads = 2/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i 's/processes = 3/processes = 4/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i 's/cheaper = 1/cheaper = 2/g' feeds/packages/net/uwsgi/files-luci-support/luci-webui.ini
sed -i 's/option timeout 30/option timeout 60/g' package/system/rpcd/files/rpcd.config
sed -i 's#20) \* 1000#60) \* 1000#g' feeds/luci/modules/luci-base/htdocs/luci-static/resources/rpc.js
# ---------- 6. 默认IP、ROOT密码设置 ----------
sed -i "s/192.168.1.1/$LAN/g" package/base-files/files/bin/config_generate
if [ -n "$ROOT_PASSWORD" ]; then
    default_password=$(openssl passwd -5 $ROOT_PASSWORD)
    sed -i "s|^root:[^:]*:|root:${default_password}:|" package/base-files/files/etc/shadow
fi
# ---------- 7. OpenAppFilter eBPF 支持 ----------
if [ "$ENABLE_OAF" = "y" ]; then
  sed -i 's/# CONFIG_BPF_SYSCALL is not set/CONFIG_BPF_SYSCALL=y/' .config
fi
# ---------- 8. Rust源码编译参数修复 ----------
sed -i 's/--set=llvm\.download-ci-llvm=true/--set=llvm.download-ci-llvm=false/' feeds/packages/lang/rust/Makefile
# ---------- 9. BBR3 PATCH（全部18个补丁，文件名逐条明确） ----------
curl -sL $mirror/doc/patch/kernel-6.6/kernel/0003-include-kernel-defaults.mk.patch | patch -p1
mkdir -p target/linux/generic/backport-6.6
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
# ---------- 10. LRNG 全部27个补丁完整文件名区块 ----------
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
' >> ./target/linux/generic/config-6.6
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
# ---------- 11. firewall4/libnftnl/nftables区块 ----------
mkdir -p package/network/config/firewall4/patches
curl -s $mirror/Customize/firewall4/Makefile > package/network/config/firewall4/Makefile
sed -i 's|$(PROJECT_GIT)/project|https://github.com/openwrt|g' package/network/config/firewall4/Makefile
curl -s $mirror/doc/patch/firewall4/firewall4_patches/990-unconditionally-allow-ct-status-dnat.patch > package/network/config/firewall4/patches/990-unconditionally-allow-ct-status-dnat.patch
curl -s $mirror/doc/patch/firewall4/firewall4_patches/999-01-firewall4-add-fullcone-support.patch > package/network/config/firewall4/patches/999-01-firewall4-add-fullcone-support.patch
curl -s $mirror/doc/patch/firewall4/firewall4_patches/999-02-firewall4-add-bcm-fullconenat-support.patch > package/network/config/firewall4/patches/999-02-firewall4-add-bcm-fullconenat-support.patch
curl -s $mirror/doc/patch/firewall4/firewall4_patches/001-fix-fw4-flow-offload.patch > package/network/config/firewall4/patches/001-fix-fw4-flow-offload.patch
curl -s $mirror/doc/patch/firewall4/100-openwrt-firewall4-add-custom-nft-command-support.patch | patch -p1
mkdir -p package/libs/libnftnl/patches
curl -s $mirror/doc/patch/firewall4/libnftnl/0001-libnftnl-add-fullcone-expression-support.patch > package/libs/libnftnl/patches/0001-libnftnl-add-fullcone-expression-support.patch
curl -s $mirror/doc/patch/firewall4/libnftnl/0002-libnftnl-add-brcm-fullcone-support.patch > package/libs/libnftnl/patches/0002-libnftnl-add-brcm-fullcone-support.patch
mkdir -p package/network/utils/nftables/patches
curl -s $mirror/doc/patch/firewall4/nftables/0001-nftables-add-fullcone-expression-support.patch > package/network/utils/nftables/patches/0001-nftables-add-fullcone-expression-support.patch
curl -s $mirror/doc/patch/firewall4/nftables/0002-nftables-add-brcm-fullconenat-support.patch > package/network/utils/nftables/patches/0002-nftables-add-brcm-fullconenat-support.patch
curl -s $mirror/doc/patch/firewall4/nftables/0003-drop-rej-file.patch > package/network/utils/nftables/patches/0003-drop-rej-file.patch
# ---------- 12. 其它 kernel/net hack补丁 ----------
curl -s $mirror/doc/patch/kernel-6.6/btf/990-btf-silence-btf-module-warning-messages.patch > target/linux/generic/hack-6.6/990-btf-silence-btf-module-warning-messages.patch
curl -s $mirror/doc/patch/kernel-6.6/arm64/312-arm64-cpuinfo-Add-model-name-in-proc-cpuinfo-for-64bit-ta.patch > target/linux/generic/hack-6.6/312-arm64-cpuinfo-Add-model-name-in-proc-cpuinfo-for-64bit-ta.patch
curl -s $mirror/doc/patch/kernel-6.6/net/952-net-conntrack-events-support-multiple-registrant.patch > target/linux/generic/hack-6.6/952-net-conntrack-events-support-multiple-registrant.patch
curl -s $mirror/doc/patch/kernel-6.6/net/982-add-bcm-fullcone-support.patch > target/linux/generic/hack-6.6/982-add-bcm-fullcone-support.patch
curl -s $mirror/doc/patch/kernel-6.6/net/983-add-bcm-fullcone-nft_masq-support.patch > target/linux/generic/hack-6.6/983-add-bcm-fullcone-nft_masq-support.patch
curl -s $mirror/doc/patch/kernel-6.6/net/601-netfilter-export-udp_get_timeouts-function.patch > target/linux/generic/hack-6.6/601-netfilter-export-udp_get_timeouts-function.patch
curl -s $mirror/doc/patch/kernel-6.6/net/953-net-patch-linux-kernel-to-support-shortcut-fe.patch > target/linux/generic/hack-6.6/953-net-patch-linux-kernel-to-support-shortcut-fe.patch
curl -s $mirror/doc/patch/kernel-6.6/igc-fix/996-intel-igc-i225-i226-disable-eee.patch > target/linux/x86/patches-6.6/996-intel-igc-i225-i226-disable-eee.patch
# =========================== 13. clone/更新自定义第三方包 ===========================

# 删除软件依赖
rm -rf feeds/packages/net/{v2ray-geodata,open-app-filter,shadowsocksr-libev,shadowsocks-rust,shadowsocks-libev}
rm -rf feeds/packages/net/{tcping,trojan,trojan-plus,tuic-client,v2ray-core,v2ray-plugin,xray-core,xray-plugin,sing-box}
rm -rf feeds/packages/net/{chinadns-ng,hysteria,mosdns,lucky,ddns-go,v2dat,golang}

# 删除软件包
rm -rf feeds/luci/applications/{luci-app-daed,luci-app-dae,luci-app-homeproxy,luci-app-openclash}
rm -rf feeds/luci/applications/{luci-app-passwall,luci-app-passwall2,luci-app-ssr-plus,luci-app-vssr}
rm -rf feeds/luci/applications/{luci-app-appfilter,luci-app-ddns-go,luci-app-lucky,luci-app-mosdns,luci-app-alist,luci-app-openlist,luci-app-airwhu}

# NFT FullCone NAT 支持
git clone https://$gitea/nft-fullcone package/new/nft-fullcone --depth=1

# IPv6 NAT (NAT6) 支持与增强
git clone https://$gitea/package_new_nat6 package/new/nat6 --depth=1

# NAT Flow 加速，提升转发性能
git clone https://$gitea/package_new_natflow package/new/natflow --depth=1

# Shortcut-fe 网络硬件加速
git clone https://$github/zhiern/shortcut-fe package/new/shortcut-fe --depth=1

# Caddy Web Server 支持
git clone https://$gitea/luci-app-caddy package/new/caddy --depth=1

# OpenAppFilter 流量管理和广告过滤
git clone https://$github/destan19/OpenAppFilter package/new/OpenAppFilter --depth=1

# luci-app-lucky 网络诊断与工具箱
git clone https://$github/gdy666/luci-app-lucky.git package/new/lucky --depth=1

# 关机（Poweroff）菜单扩展
git clone https://github.com/sirpdboy/luci-app-poweroffdevice package/new/poweroff --depth=1
mv -n package/new/poweroff/luci-app-poweroffdevice package/new/luci-app-poweroffdevice && rm -rf package/new/poweroff

# WebDAV 网络文件挂载和管理
git clone https://$github/sbwml/luci-app-webdav package/new/luci-app-webdav --depth=1

# Quickfile 快速文件管理与分享
git clone https://$github/sbwml/luci-app-quickfile package/new/quickfile --depth=1

# SSR/Passwall(Helloworld) 插件聚合
git clone https://$github/sbwml/openwrt_helloworld package/new/helloworld -b v5 --depth=1

# MOSDNS v5 DNS高性能服务器与广告过滤
# git clone https://$github/sbwml/luci-app-mosdns -b v5 package/new/mosdns --depth=1
# mv -n mosdns/{luci-app-mosdns,mosdns,v2dat} ./helloworld && rm -rf mosdns

# OpenList2 订阅与批量代理规则管理
git clone https://$github/sbwml/luci-app-openlist2 package/new/openlist --depth=1

# unzip 工具（解压支持）
rm -rf feeds/packages/utils/unzip
git clone https://$github/sbwml/feeds_packages_utils_unzip feeds/packages/utils/unzip

# ARM 性能监控自定义
git clone https://$gitea/autocore-arm package/new/autocore-arm --depth=1

# Argon 主题界面美化
git clone https://github.com/grandway2025/argon package/new/luci-theme-argon --depth=1

# AdvancedPlus 进阶设置工具
git clone https://$github/sirpdboy/luci-app-advancedplus.git package/new/luci-app-advancedplus --depth=1

# Kucat 主题界面美化
git clone https://$github/sirpdboy/luci-theme-kucat.git package/new/kucat --depth=1
mv -n package/new/kucat/luci-theme-kucat package/new/luci-theme-kucat && rm -rf package/new/kucat

# sbwml杂项包（部分工具和扩展）
git clone https://$github/sbwml/openwrt_pkgs package/new/custom --depth=1
rm -rf package/new/custom/luci-app-adguardhome       

# AdGuardHome 广告拦截与家庭网络安全
git clone https://$gitea/luci-app-adguardhome package/new/luci-app-adguardhome --depth=1

# Taskplan 任务计划管理
git clone https://github.com/sirpdboy/luci-app-taskplan package/new/luci-app-taskplan --depth=1

# Dockerman 容器管理（适配新版 feeds/luci/applications 目录）
rm -rf feeds/luci/applications/luci-app-dockerman
git clone https://github.com/sirpdboy/luci-app-dockerman.git feeds/luci/applications/luci-app-dockerman --depth=1
rm -rf feeds/packages/utils/{docker,dockerd,containerd,runc}
git clone https://$github/sbwml/packages_utils_docker feeds/packages/utils/docker
git clone https://$github/sbwml/packages_utils_dockerd feeds/packages/utils/dockerd
git clone https://$github/sbwml/packages_utils_containerd feeds/packages/utils/containerd
git clone https://$github/sbwml/packages_utils_runc feeds/packages/utils/runc

# 默认基础设置（By grandway2025）
git clone https://$github/grandway2025/default-settings package/new/default-settings -b openwrt-24.10 --depth=1

# ============ 14. Feeds文件美化及特殊配置 ============
##### TTYD 界面和启动设置
sed -i 's/services/system/g' feeds/luci/applications/luci-app-ttyd/root/usr/share/luci/menu.d/luci-app-ttyd.json  # 菜单归属到系统
sed -i '3 a\\t\t"order": 50,' feeds/luci/applications/luci-app-ttyd/root/usr/share/luci/menu.d/luci-app-ttyd.json # 菜单排序
sed -i 's/procd_set_param stdout 1/procd_set_param stdout 0/g' feeds/packages/utils/ttyd/files/ttyd.init           # 关闭ttyd标准输出
sed -i 's/procd_set_param stderr 1/procd_set_param stderr 0/g' feeds/packages/utils/ttyd/files/ttyd.init           # 关闭ttyd标准错误

##### DDNS启动修正
sed -i '/boot()/,+2d' feeds/packages/net/ddns-scripts/files/etc/init.d/ddns  # 修复 init/boot 错误

##### FRPC 启动脚本和参数美化
sed -i 's/procd_set_param stdout $stdout/procd_set_param stdout 0/g' feeds/packages/net/frp/files/frpc.init
sed -i 's/procd_set_param stderr $stderr/procd_set_param stderr 0/g' feeds/packages/net/frp/files/frpc.init
sed -i 's/stdout stderr //g' feeds/packages/net/frp/files/frpc.init
sed -i '/stdout:bool/d;/stderr:bool/d' feeds/packages/net/frp/files/frpc.init
sed -i '/stdout/d;/stderr/d' feeds/packages/net/frp/files/frpc.config
sed -i 's/env conf_inc/env conf_inc enable/g' feeds/packages/net/frp/files/frpc.init
sed -i "s/'conf_inc:list(string)'/& \\\\/" feeds/packages/net/frp/files/frpc.init
sed -i "/conf_inc:list/a\\\t\t\'enable:bool:0\'" feeds/packages/net/frp/files/frpc.init
sed -i '/procd_open_instance/i\\t\[ "$enable" -ne 1 \] \&\& return 1\n' feeds/packages/net/frp/files/frpc.init

##### NATMAP 启动参数
sed -i 's/log_stdout:bool:1/log_stdout:bool:0/g;s/log_stderr:bool:1/log_stderr:bool:0/g' feeds/packages/net/natmap/files/natmap.init

##### NLBWMON 菜单归类
sed -i 's/services/network/g' feeds/luci/applications/luci-app-nlbwmon/root/usr/share/luci/menu.d/luci-app-nlbwmon.json
sed -i 's/services/network/g' feeds/luci/applications/luci-app-nlbwmon/htdocs/luci-static/resources/view/nlbw/config.js

##### netdata 修改日志输出
sed -i 's/syslog/none/g' feeds/packages/admin/netdata/files/netdata.conf

##### Libsodium 编译参数修正（mips16/lto兼容）
sed -i 's/no-mips16 no-lto/no-mips16/g' feeds/packages/libs/libsodium/Makefile


# ============ 15. rootfs美化与文件定制 ============

##### shell界面美化及环境变量 #####
sed -i 's#\\u@\\h:\\w\\\$#\\[\\e[32;1m\\][\\u@\\h\\[\\e[0m\\] \\[\\033[01;34m\\]\\W\\[\\033[00m\\]\\[\\e[32;1m\\]]\\[\\e[0m\\]\\\$#g' package/base-files/files/etc/profile
sed -ri 's/(export PATH=")[^"]*/\1%PATH%:\/opt\/bin:\/opt\/sbin:\/opt\/usr\/bin:\/opt\/usr\/sbin/' package/base-files/files/etc/profile
sed -i '/PS1/a\export TERM=xterm-color' package/base-files/files/etc/profile
sed -i '\#export ENV=/etc/shinit#a export HISTCONTROL=ignoredups' package/base-files/files/etc/profile

##### 切换Bash默认shell #####
sed -i 's#ash#bash#g' package/base-files/files/etc/passwd

##### Bash配置定制 #####
mkdir -p files/root
curl -so files/root/.bash_profile $mirror/doc/files/root/.bash_profile      # Bash登录环境
curl -so files/root/.bashrc $mirror/doc/files/root/.bashrc                  # Bash执行环境

##### sysctl优化配置 #####
mkdir -p files/etc/sysctl.d
curl -so files/etc/sysctl.d/10-default.conf $mirror/doc/files/etc/sysctl.d/10-default.conf
curl -so files/etc/sysctl.d/15-vm-swappiness.conf $mirror/doc/files/etc/sysctl.d/15-vm-swappiness.conf
curl -so files/etc/sysctl.d/16-udp-buffer-size.conf $mirror/doc/files/etc/sysctl.d/16-udp-buffer-size.conf

##### ZeroWrt选项菜单/版本文件 #####
mkdir -p files/bin
curl -so files/root/version.txt $mirror/doc/files/root/version.txt
curl -so files/bin/ZeroWrt $mirror/doc/files/bin/ZeroWrt
chmod +x files/bin/ZeroWrt
chmod 644 files/root/version.txt

##### key-build.pub 导入 #####
curl -so files/root/key-build.pub https://opkg.kejizero.online/key-build.pub
chmod 644 files/root/key-build.pub

##### NTP服务器优化 #####
sed -i 's/0.openwrt.pool.ntp.org/ntp1.aliyun.com/g' package/base-files/files/bin/config_generate
sed -i 's/1.openwrt.pool.ntp.org/ntp2.aliyun.com/g' package/base-files/files/bin/config_generate
sed -i 's/2.openwrt.pool.ntp.org/time1.cloud.tencent.com/g' package/base-files/files/bin/config_generate
sed -i 's/3.openwrt.pool.ntp.org/time2.cloud.tencent.com/g' package/base-files/files/bin/config_generate

##### 作者信息与版本标记 #####
sed -i "s/DISTRIB_DESCRIPTION='*.*'/DISTRIB_DESCRIPTION='OpenWrt-$(date +%Y%m%d)'/g"  package/base-files/files/etc/openwrt_release
sed -i "s/DISTRIB_REVISION='*.*'/DISTRIB_REVISION=' By grandway2025'/g" package/base-files/files/etc/openwrt_release
sed -i "s|^OPENWRT_RELEASE=\".*\"|OPENWRT_RELEASE=\"OpenWrt定制版 @R$(date +%Y%m%d) BY grandway2025\"|" package/base-files/files/usr/lib/os-release
sed -i "/BUILD_DATE/d" package/base-files/files/usr/lib/os-release
sed -i "/BUILD_ID/aBUILD_DATE=\"$CURRENT_DATE\"" package/base-files/files/usr/lib/os-release

##### rc.local 自定义开机脚本 #####
cat > ./package/base-files/files/etc/rc.local <<'EOF'
#!/bin/sh
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
EOF
# ---------- 16. opkg源 feed 定制 ----------
mkdir -p files/etc/opkg
cat > files/etc/opkg/distfeeds.conf <<EOF
src/gz openwrt_base https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/24.10.2/packages/x86_64/base
src/gz openwrt_luci https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/24.10.2/packages/x86_64/luci
src/gz openwrt_packages https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/24.10.2/packages/x86_64/packages
src/gz openwrt_routing https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/24.10.2/packages/x86_64/routing
src/gz openwrt_telephony https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/24.10.2/packages/x86_64/telephony
EOF
# ---------- 17. 临时文件清理 ----------
rm -rf tmp/*
# ========== END OF SCRIPT ==========
