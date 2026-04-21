#!/usr/bin/env bash
set -euo pipefail

REMOTE="root@5860-proxmox"
BASE="/srv/service-fabric"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

rand() {
  openssl rand -base64 36 | tr -d '\n'
}

ensure_sshpass() {
  command -v sshpass >/dev/null 2>&1 || {
    echo "[ERROR] sshpass is required on the local machine for this helper." >&2
    exit 1
  }
}

ensure_sshpass

NETBOX_DB_PASSWORD="$(rand)"
NETBOX_REDIS_PASSWORD="$(rand)"
NETBOX_REDIS_CACHE_PASSWORD="$(rand)"
NETBOX_SECRET_KEY="$(rand)"
NETBOX_API_TOKEN_PEPPER="$(rand)"
NETBOX_SUPERUSER_PASSWORD="$(rand)"
NETBOX_SUPERUSER_API_TOKEN="$(rand)"
TECHNITIUM_ADMIN_PASSWORD="$(rand)"

cat > /tmp/netbox.env <<EOF
DB_HOST=postgres
DB_NAME=netbox
DB_USER=netbox
DB_PASSWORD=${NETBOX_DB_PASSWORD}
REDIS_HOST=redis
REDIS_PASSWORD=${NETBOX_REDIS_PASSWORD}
REDIS_DATABASE=0
REDIS_SSL=false
REDIS_INSECURE_SKIP_TLS_VERIFY=false
REDIS_CACHE_HOST=redis-cache
REDIS_CACHE_PASSWORD=${NETBOX_REDIS_CACHE_PASSWORD}
REDIS_CACHE_DATABASE=1
REDIS_CACHE_SSL=false
REDIS_CACHE_INSECURE_SKIP_TLS_VERIFY=false
SECRET_KEY=${NETBOX_SECRET_KEY}
API_TOKEN_PEPPER_1=${NETBOX_API_TOKEN_PEPPER}
EMAIL_FROM=netbox@lab.sounio
EMAIL_SERVER=localhost
EMAIL_PORT=25
EMAIL_TIMEOUT=5
EMAIL_USERNAME=netbox
EMAIL_PASSWORD=
EMAIL_USE_SSL=false
EMAIL_USE_TLS=false
MEDIA_ROOT=/opt/netbox/netbox/media
GRAPHQL_ENABLED=true
METRICS_ENABLED=false
WEBHOOKS_ENABLED=true
SKIP_SUPERUSER=false
ALLOWED_HOSTS=netbox.lab.sounio,192.168.3.207,10.30.0.1
EOF

cat > /tmp/bootstrap.env <<EOF
SUPERUSER_NAME=admin
SUPERUSER_EMAIL=admin@lab.sounio
SUPERUSER_PASSWORD=${NETBOX_SUPERUSER_PASSWORD}
SUPERUSER_API_TOKEN=${NETBOX_SUPERUSER_API_TOKEN}
EOF

cat > /tmp/postgres.env <<EOF
POSTGRES_DB=netbox
POSTGRES_USER=netbox
POSTGRES_PASSWORD=${NETBOX_DB_PASSWORD}
EOF

cat > /tmp/redis.env <<EOF
REDIS_PASSWORD=${NETBOX_REDIS_PASSWORD}
EOF

cat > /tmp/redis-cache.env <<EOF
REDIS_PASSWORD=${NETBOX_REDIS_CACHE_PASSWORD}
EOF

cat > /tmp/technitium.env <<EOF
DNS_SERVER_DOMAIN=svc10g.lab.sounio
DNS_SERVER_ADMIN_PASSWORD=${TECHNITIUM_ADMIN_PASSWORD}
DNS_SERVER_FORWARDERS=192.168.3.1
DNS_SERVER_RECURSION=UseSpecifiedNetworkACL
DNS_SERVER_RECURSION_NETWORK_ACL=127.0.0.1,10.30.0.0/24,10.100.100.0/24,10.200.0.0/24,10.210.0.0/24,192.168.3.0/24
DNS_SERVER_LOG_USING_LOCAL_TIME=true
EOF

sshpass -p 'Urso1982!' ssh -o StrictHostKeyChecking=no "${REMOTE}" '
  set -euo pipefail
  apt-get update >/dev/null
  DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose curl jq >/dev/null
  systemctl enable --now docker
  mkdir -p '"${BASE}"'/registry/data/dockerhub '"${BASE}"'/registry/data/ghcr '"${BASE}"'/registry/data/registry-k8s '"${BASE}"'/technitium/config '"${BASE}"'/netbox/env '"${BASE}"'/netbox/media '"${BASE}"'/netbox/reports '"${BASE}"'/netbox/scripts '"${BASE}"'/netbox/postgres '"${BASE}"'/netbox/redis '"${BASE}"'/netbox/redis-cache
'

sshpass -p 'Urso1982!' scp -q -o StrictHostKeyChecking=no "${REPO_DIR}/service-fabric-stack.compose.yaml" "${REMOTE}:${BASE}/service-fabric-stack.compose.yaml"
sshpass -p 'Urso1982!' scp -q -o StrictHostKeyChecking=no "${REPO_DIR}/registry-cache/dockerhub.yml" "${REMOTE}:${BASE}/registry/dockerhub.yml"
sshpass -p 'Urso1982!' scp -q -o StrictHostKeyChecking=no "${REPO_DIR}/registry-cache/ghcr.yml" "${REMOTE}:${BASE}/registry/ghcr.yml"
sshpass -p 'Urso1982!' scp -q -o StrictHostKeyChecking=no "${REPO_DIR}/registry-cache/registry-k8s.yml" "${REMOTE}:${BASE}/registry/registry-k8s.yml"
sshpass -p 'Urso1982!' scp -q -o StrictHostKeyChecking=no "${REPO_DIR}/seed-netbox.py" "${REMOTE}:${BASE}/seed-netbox.py"

sshpass -p 'Urso1982!' scp -q -o StrictHostKeyChecking=no /tmp/netbox.env "${REMOTE}:${BASE}/netbox/env/netbox.env"
sshpass -p 'Urso1982!' scp -q -o StrictHostKeyChecking=no /tmp/bootstrap.env "${REMOTE}:${BASE}/netbox/env/bootstrap.env"
sshpass -p 'Urso1982!' scp -q -o StrictHostKeyChecking=no /tmp/postgres.env "${REMOTE}:${BASE}/netbox/env/postgres.env"
sshpass -p 'Urso1982!' scp -q -o StrictHostKeyChecking=no /tmp/redis.env "${REMOTE}:${BASE}/netbox/env/redis.env"
sshpass -p 'Urso1982!' scp -q -o StrictHostKeyChecking=no /tmp/redis-cache.env "${REMOTE}:${BASE}/netbox/env/redis-cache.env"
sshpass -p 'Urso1982!' scp -q -o StrictHostKeyChecking=no /tmp/technitium.env "${REMOTE}:${BASE}/technitium/technitium.env"

sshpass -p 'Urso1982!' ssh -o StrictHostKeyChecking=no "${REMOTE}" '
  set -euo pipefail
  cd '"${BASE}"'
  if docker compose version >/dev/null 2>&1; then
    docker compose -f service-fabric-stack.compose.yaml up -d
  else
    docker-compose -f service-fabric-stack.compose.yaml up -d
  fi
'

echo "NETBOX_SUPERUSER_PASSWORD=${NETBOX_SUPERUSER_PASSWORD}"
echo "NETBOX_SUPERUSER_API_TOKEN=${NETBOX_SUPERUSER_API_TOKEN}"
echo "TECHNITIUM_ADMIN_PASSWORD=${TECHNITIUM_ADMIN_PASSWORD}"
