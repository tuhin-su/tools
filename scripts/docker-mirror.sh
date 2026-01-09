#!/bin/sh

echo "🌎 Discovering ALL available Docker mirrors..."

# ---------------------------------------------------------
# AUTO DISCOVERY FROM DNS + WELL KNOWN SOURCES
# ---------------------------------------------------------

DISCOVERED_MIRRORS=$(cat /dev/null)

# 1. Search DNS for docker mirror hosts
DNS_CANDIDATES=$(dig +short docker.mirrors.* ANY | tr -d '"' 2>/dev/null)

# 2. Search wildcard domains for mirrors
for domain in mirrors.aliyun.com dockerproxy.com dockerhub timeweb cloud 163.com npmmirror.com daocloud.io sjtug.sjtu.edu.cn yandex.ru; do
    host docker.$domain >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        DISCOVERED_MIRRORS="$DISCOVERED_MIRRORS https://docker.$domain"
    fi
done

# 3. Known Public Mirrors (fallback baseline)
STATIC_MIRRORS="
https://mirror.gcr.io
https://docker.nxtgen.com
https://dockerhub.timeweb.cloud
https://dockerhub.icu
https://ghcr.dockerproxy.com
https://dockerproxy.net
https://dockermirror.com
https://registry.aliyuncs.com
https://registry.cn-hangzhou.aliyuncs.com
https://registry.docker-cn.com
https://docker.mirrors.ustc.edu.cn
https://docker.m.daocloud.io
https://hub-mirror.c.163.com
https://mirror.nju.edu.cn/docker
https://registry.npmmirror.com/docker
https://docker.1ms.run
https://dockerpull.org
https://dockerpull.com
https://docker-images.mirrors.sjtug.sjtu.edu.cn
https://mirror.surf
https://mirror.yandex.ru/docker
https://asia-southeast1-docker.pkg.dev
https://us-east1.docker.pkg.dev
https://us-central1-docker.pkg.dev
https://europe-west1-docker.pkg.dev
https://asia-northeast1-docker.pkg.dev
"

# Merge all
ALL_MIRRORS="$STATIC_MIRRORS $DISCOVERED_MIRRORS $DNS_CANDIDATES"

# Remove duplicates
ALL_MIRRORS=$(printf "%s\n" $ALL_MIRRORS | sort -u)

echo "🔍 Total mirrors found: $(printf '%s\n' $ALL_MIRRORS | wc -l)"

# ---------------------------------------------------------
# TEST MIRRORS FOR SPEED + AVAILABILITY
# ---------------------------------------------------------

FASTEST=""
BEST_TIME=999999

echo "⚡ Testing mirrors to find fastest..."

for URL in $ALL_MIRRORS; do
    echo "\n⏱ Testing: $URL"

    START=$(date +%s%3N)
    wget -q --spider --timeout=2 $URL
    RESULT=$?
    END=$(date +%s%3N)

    if [ $RESULT -ne 0 ]; then
        echo "❌ Unreachable"
        continue
    fi

    TIME=$((END - START))
    echo "✔ Response: ${TIME}ms"

    if [ $TIME -lt $BEST_TIME ]; then
        BEST_TIME=$TIME
        FASTEST=$URL
    fi
done

if [ -z "$FASTEST" ]; then
    echo "❌ No mirrors available!"
    exit 1
fi

echo "\n🌍 FASTEST MIRROR FOUND:"
echo "➡ $FASTEST   (${BEST_TIME}ms)"

# ---------------------------------------------------------
# APPLY CONFIG
# ---------------------------------------------------------

mkdir -p /etc/docker

cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["$FASTEST"]
}
EOF

echo "✔ Updated /etc/docker/daemon.json"
echo "🔄 Restarting Docker..."

service docker restart

echo "\n🎉 DONE! Docker is using:"
docker info | grep -i mirror
