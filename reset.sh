#!/usr/bin/env bash
set -euo pipefail
umask 077

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo bash $0"
    exit 1
fi

SERVICE="socks5-proxy.service"
CONFIG="/etc/socks5-proxy.conf"
ENV_FILE="/etc/socks5-proxy.env"
CREDENTIALS="/root/socks5-credentials.txt"
SOCKS_USER="proxyauthuser"

if [[ ! -f "$CONFIG" || ! -f "$ENV_FILE" || ! -f "$CREDENTIALS" ]] ||
    ! id "$SOCKS_USER" >/dev/null 2>&1; then
    echo "ERROR: Existing SOCKS5 installation not found. Run setup.sh first."
    exit 1
fi

# Read only the required values; never execute the saved environment file.
OLD_PORT="$(sed -n 's/^SOCKS_PORT=//p' "$ENV_FILE")"
EXT_IF="$(sed -n 's/^EXT_IF=//p' "$ENV_FILE")"
if [[ ! "$OLD_PORT" =~ ^[0-9]+$ || -z "$EXT_IF" ]]; then
    echo "ERROR: Invalid saved SOCKS5 configuration."
    exit 1
fi

while true; do
    SOCKS_PORT="$(shuf -i 20000-60000 -n 1)"
    [[ "$SOCKS_PORT" == "$OLD_PORT" ]] && continue
    # Consume all output to avoid grep -q / pipefail early-exit issues.
    if ! ss -ltnH | awk '{print $4}' | grep -E ":${SOCKS_PORT}$" >/dev/null; then
        break
    fi
done

SOCKS_PASS="$(openssl rand -hex 16)"
PUBLIC_IP="$(curl -4 --fail --silent --show-error --connect-timeout 5 --max-time 10 https://api.ipify.org 2>/dev/null || true)"
if [[ ! "$PUBLIC_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    PUBLIC_IP="YOUR_SERVER_IP"
    echo "WARNING: Could not detect public IPv4. Replace YOUR_SERVER_IP in the SOCKS5 URL."
fi
SOCKS_URL="socks5://${SOCKS_USER}:${SOCKS_PASS}@${PUBLIC_IP}:${SOCKS_PORT}"

WORK_DIR="$(mktemp -d)"
APPLYING=0
OLD_HASH="$(getent shadow "$SOCKS_USER" | cut -d: -f2)"
if [[ -z "$OLD_HASH" ]]; then
    rm -rf -- "$WORK_DIR"
    echo "ERROR: Could not read the existing password hash."
    exit 1
fi

cleanup() {
    local status=$?
    trap - EXIT
    if (( status != 0 && APPLYING == 1 )); then
        echo "ERROR: Reset failed; restoring previous settings."
        cp -- "$WORK_DIR/config" "$CONFIG" || true
        cp -- "$WORK_DIR/env" "$ENV_FILE" || true
        cp -- "$WORK_DIR/credentials" "$CREDENTIALS" || true
        usermod --password "$OLD_HASH" "$SOCKS_USER" || true
        systemctl restart "$SERVICE" || true
    fi
    rm -rf -- "$WORK_DIR"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cp -- "$CONFIG" "$WORK_DIR/config"
cp -- "$ENV_FILE" "$WORK_DIR/env"
cp -- "$CREDENTIALS" "$WORK_DIR/credentials"

# Preserve existing access rules and change only the listener port.
sed -E "s/^(internal: 0\.0\.0\.0 port = )[0-9]+$/\1${SOCKS_PORT}/" \
    "$CONFIG" > "$WORK_DIR/new-config"
if ! grep -Fx "internal: 0.0.0.0 port = ${SOCKS_PORT}" "$WORK_DIR/new-config" >/dev/null; then
    echo "ERROR: Could not update the listener port."
    exit 1
fi
/usr/sbin/danted -V -f "$WORK_DIR/new-config"

cat > "$WORK_DIR/new-env" <<EOF
SOCKS_PORT=${SOCKS_PORT}
SOCKS_USER=${SOCKS_USER}
SOCKS_PASS=${SOCKS_PASS}
EXT_IF=${EXT_IF}
SOCKS_URL=${SOCKS_URL}
EOF
cat > "$WORK_DIR/new-credentials" <<EOF
SOCKS5 PORT     : ${SOCKS_PORT}
SOCKS5 USERNAME : ${SOCKS_USER}
SOCKS5 PASSWORD : ${SOCKS_PASS}
SOCKS5 URL      : ${SOCKS_URL}
EOF

APPLYING=1
printf '%s:%s\n' "$SOCKS_USER" "$SOCKS_PASS" | chpasswd
install -m 600 "$WORK_DIR/new-config" "$CONFIG"
install -m 600 "$WORK_DIR/new-env" "$ENV_FILE"
install -m 600 "$WORK_DIR/new-credentials" "$CREDENTIALS"
systemctl restart "$SERVICE"
sleep 1
systemctl is-active --quiet "$SERVICE"
ss -ltnH | awk '{print $4}' | grep -E ":${SOCKS_PORT}$" >/dev/null
APPLYING=0

echo
echo "SOCKS5 RESET COMPLETE"
cat "$CREDENTIALS"
echo
echo "Credentials saved: ${CREDENTIALS}"
echo "Update your client and firewall/security group to use port ${SOCKS_PORT}."
