#!/bin/bash

mkdir -p files/etc/openclash/core
mkdir -p files/etc/config

# CLASH_META_URL="https://github.com/vernesong/mihomo/releases/download/Prerelease-Alpha/mihomo-linux-amd64-alpha-smart-5bc3f7d.gz"
CLASH_META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/smart/clash-linux-amd64.tar.gz"
GEOIP_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
GEOSITE_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
MODEL_URL="https://github.com/vernesong/mihomo/releases/download/LightGBM-Model/model-large.bin"
CLASH_URL="https://github.com/grandway2025/Actions-OpenWrt/raw/refs/heads/main/files/openclash"
NIKKI_URL="https://github.com/grandway2025/Actions-OpenWrt/raw/refs/heads/main/files/nikki"

# wget -qO- $CLASH_META_URL | gzip -d > files/etc/openclash/core/mihomo-linux-amd64
wget -qO- $CLASH_META_URL | tar xOvz > files/etc/openclash/core/clash_meta
wget -qO- $GEOIP_URL > files/etc/openclash/GeoIP.dat
wget -qO- $GEOSITE_URL > files/etc/openclash/GeoSite.dat
wget -qO- $MODEL_URL > files/etc/openclash/model.bin
wget -qO- $CLASH_URL > files/etc/config/openclash
wget -qO- $NIKKI_URL > files/etc/config/nikki

chmod +x files/etc/openclash/core/clash*
chmod +x files/etc/config/openclash
chmod +x files/etc/config/nikki
