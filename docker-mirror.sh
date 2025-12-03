#!/bin/sh

# ---------------------------
# Worldwide Docker Mirrors
# ---------------------------
MIRRORS="
https://mirror.gcr.io
https://registry.npmmirror.com/docker
https://docker.nxtgen.com
https://registry.aliyuncs.com
https://docker.mirrors.ustc.edu.cn
https://mirror.nju.edu.cn/docker
https://hub-mirror.c.163.com
https://docker.m.daocloud.io
https://dockerhub.timeweb.cloud
https://dockerhub.icu
https://registry.docker-cn.com
https://ghcr.dockerproxy.com
"

echo "🌐 Auto Selecting Fastest Worldwide Docker Mirror"
echo "🔍 Testing mirrors..."

FASTEST=""
BEST_TIME=999999

for URL in $MIRRORS; do
    echo "\n⏱ Testing: $URL"

    # Measure latency using HEAD request
    START=$(date +%s%3N)
    wget -q --spider --timeout=2 $URL
    RESULT=$?
    END=$(date +%s%3N)

    if [ $RESULT -ne 0 ]; then
        echo "❌ Mirror unreachable"
        continue
    fi

    TIME=$((END - START))
    echo "✔ Response Time: ${TIME}ms"

    if [ $TIME -lt $BEST_TIME ]; then
        BEST_TIME=$TIME
        FASTEST=$URL
    fi
done

if [ -z "$FASTEST" ]; then
    echo "❌ No mirrors reachable! Check internet."
    exit 1
fi

echo "\n🌍 Fastest Worldwide Mirror: $FASTEST (${BEST_TIME}ms)"

# ---------------------------
# Configure Docker
# ---------------------------
mkdir -p /etc/docker

cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["$FASTEST"]
}
EOF

echo "✔ Updated /etc/docker/daemon.json"

# Restart Docker (Alpine)
echo "🔄 Restarting Docker..."
service docker restart

echo "\n🎉 Docker is now using:"
docker info | grep -i "registry mirrors"
