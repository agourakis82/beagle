#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-kubeconfig.sh"
NAMESPACE="${NAMESPACE:-slurm-pilot}"

DB_NAME="${DB_NAME:-slurm_acct_db}"
DB_USER="${DB_USER:-slurm}"
DB_PASSWORD="${DB_PASSWORD:-$(openssl rand -hex 16)}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-$(openssl rand -hex 16)}"
DB_BIND_ADDRESS="${DB_BIND_ADDRESS:-10.100.100.2}"

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y mariadb-server

kubectl --kubeconfig "${KUBECONFIG_PATH}" -n "${NAMESPACE}" create secret generic mariadb-password \
  --from-literal=password="${DB_PASSWORD}" \
  --dry-run=client -o yaml | kubectl --kubeconfig "${KUBECONFIG_PATH}" apply -f -

mysqladmin -u root password "${DB_ROOT_PASSWORD}" 2>/dev/null || true

cat >/root/.my.cnf <<EOF
[client]
user=root
password=${DB_ROOT_PASSWORD}
EOF
chmod 600 /root/.my.cnf

cat >/etc/mysql/mariadb.conf.d/60-slurm-pilot.cnf <<EOF
[mysqld]
bind-address = ${DB_BIND_ADDRESS}
innodb_buffer_pool_size = 256M
max_connections = 256
EOF

systemctl enable mariadb
systemctl restart mariadb

mysql <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
EOF
