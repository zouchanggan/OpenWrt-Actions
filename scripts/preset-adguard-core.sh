#!/bin/bash

mkdir -p files/usr/bin
mkdir -p files/etc

AGH_CORE=$(curl -sL https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest | grep /AdGuardHome_linux_${1} | awk -F '"' '{print $4}')
AGH_YAML="https://github.com/grandway2025/Actions-OpenWrt/raw/refs/heads/main/files/AdGuardHome.yaml"

wget -qO- $AGH_CORE | tar xOvz > files/usr/bin/AdGuardHome
wget -qO- $AGH_YAML > files/etc/AdGuardHome.yaml

chmod +x files/usr/bin/AdGuardHome
chmod +x files/etc/AdGuardHome.yaml
