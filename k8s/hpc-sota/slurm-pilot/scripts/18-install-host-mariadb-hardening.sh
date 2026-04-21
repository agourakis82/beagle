#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

install -D -m 0644 "${REPO_ROOT}/mysql/61-slurm-pilot-hardening.cnf" /etc/mysql/mariadb.conf.d/61-slurm-pilot-hardening.cnf
install -D -m 0755 "${REPO_ROOT}/scripts/backup-host-mariadb.sh" /usr/local/sbin/slurm-pilot-mariadb-backup.sh
install -D -m 0644 "${REPO_ROOT}/systemd/slurm-pilot-mariadb-backup.service" /etc/systemd/system/slurm-pilot-mariadb-backup.service
install -D -m 0644 "${REPO_ROOT}/systemd/slurm-pilot-mariadb-backup.timer" /etc/systemd/system/slurm-pilot-mariadb-backup.timer

systemctl daemon-reload
systemctl restart mariadb
systemctl enable --now slurm-pilot-mariadb-backup.timer
systemctl start slurm-pilot-mariadb-backup.service

echo "---mariadb-active---"
systemctl is-active mariadb
echo "---backup-timer---"
systemctl is-active slurm-pilot-mariadb-backup.timer
systemctl is-enabled slurm-pilot-mariadb-backup.timer
