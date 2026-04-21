#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: prepare-5860-mok-enrollment.sh [--queue]

Without flags:
  - shows Secure Boot state
  - checks the two known NVIDIA/DKMS signing keys
  - tells you exactly what to do next

With --queue:
  - runs mokutil --import for both keys
  - you will be prompted for a one-time enrollment password
EOF
}

queue=false
if [[ $# -gt 1 ]]; then
  usage
  exit 1
fi
if [[ $# -eq 1 ]]; then
  case "$1" in
    --queue) queue=true ;;
    *)
      usage
      exit 1
      ;;
  esac
fi

keys=(
  /var/lib/shim-signed/mok/MOK.der
  /var/lib/dkms/mok.pub
)

echo "=== Secure Boot ==="
mokutil --sb-state || true
echo

echo "=== Key Presence ==="
for key in "${keys[@]}"; do
  if [[ -f "$key" ]]; then
    printf 'present: %s\n' "$key"
  else
    printf 'missing: %s\n' "$key"
  fi
done
echo

echo "=== Enrollment Status ==="
for key in "${keys[@]}"; do
  if [[ -f "$key" ]]; then
    mokutil --test-key "$key" || true
  fi
done
echo

echo "=== Certificates ==="
for key in "${keys[@]}"; do
  if [[ -f "$key" ]]; then
    echo "## $key"
    openssl x509 -inform DER -in "$key" -noout -subject -issuer -fingerprint -sha256 2>/dev/null \
      || openssl x509 -in "$key" -noout -subject -issuer -fingerprint -sha256 2>/dev/null \
      || true
  fi
done
echo

if [[ "$queue" == true ]]; then
  echo "=== Queueing MOK Enrollment ==="
  mokutil --import "${keys[@]}"
  cat <<'EOF'

Queued. Next step:
  1. reboot the host
  2. in the blue MOK screen:
     - Enroll MOK
     - Continue
     - Yes
     - enter the one-time enrollment password
     - Reboot
EOF
else
  cat <<'EOF'
Next step to queue enrollment:
  mokutil --import /var/lib/shim-signed/mok/MOK.der /var/lib/dkms/mok.pub

Then reboot and approve the keys in the blue MOK screen.

Reference:
  5860-secure-boot-mok.md
EOF
fi
