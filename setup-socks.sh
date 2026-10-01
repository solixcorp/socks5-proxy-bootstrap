#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# Debian Random SOCKS5 Installer
# - Random port
# - Random username/password
# - SOCKS5 username/password authentication
# - systemd auto start
# - Restart forever on crash
# ==========================================================

if [[ $EUID -ne 0 ]]; then
    echo "Run as root:"
    echo "  sudo bash $0"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "[1/7] Installing packages..."
apt-get update
apt-get install -y dante-server openssl iproute2 curl

# 기존 기본 danted 서비스와 충돌 방지
systemctl disable --now danted.service 2>/dev/null || true


echo "[2/7] Detecting external interface..."

EXT_IF="$(
    ip -4 route get 1.1.1.1 2>/dev/null |
    awk '{
        for(i=1;i<=NF;i++) {
            if($i=="dev") {
                print $(i+1)
                exit
            }
        }
    }'
)"

if [[ -z "${EXT_IF}" ]]; then
    echo "ERROR: Could not detect external network interface."
    exit 1
fi

echo "External interface: ${EXT_IF}"


echo "[3/7] Generating random SOCKS5 port..."

while true; do
    SOCKS_PORT="$(shuf -i 20000-60000 -n 1)"

    if ! ss -ltnH | awk '{print $4}' | grep -qE ":${SOCKS_PORT}$"; then
        break
    fi
done


echo "[4/7] Generating random credentials..."

SOCKS_USER="s5_$(openssl rand -hex 5)"
SOCKS_PASS="$(openssl rand -hex 16)"

# 만약 재설치라면 이전에 이 스크립트가 만든 계정 제거
if [[ -f /etc/random-socks5.env ]]; then
    OLD_USER="$(grep '^SOCKS_USER=' /etc/random-socks5.env 2>/dev/null | cut -d= -f2- || true)"

    if [[ -n "${OLD_USER}" ]] && id "${OLD_USER}" >/dev/null 2>&1; then
        userdel "${OLD_USER}" 2>/dev/null || true
    fi
fi

# SOCKS 인증 전용 로컬 계정
useradd \
    --no-create-home \
    --shell /usr/sbin/nologin \
    "${SOCKS_USER}"

echo "${SOCKS_USER}:${SOCKS_PASS}" | chpasswd


echo "[5/7] Writing Dante configuration..."

cat > /etc/danted-random.conf <<EOF
logoutput: stderr

internal: 0.0.0.0 port = ${SOCKS_PORT}
external: ${EXT_IF}

# username/password 인증에 privileged user가 필요함
user.privileged: root
user.unprivileged: nobody

clientmethod: none
socksmethod: username

# 연결 자체는 허용
client pass {
    from: 0.0.0.0/0
    to: 0.0.0.0/0
    log: error
}

# 실제 SOCKS 요청은 username/password 필수
socks pass {
    from: 0.0.0.0/0
    to: 0.0.0.0/0
    command: connect bind udpassociate
    socksmethod: username
    log: error
}
EOF

chmod 600 /etc/danted-random.conf

# 설정 오류가 있으면 서비스 등록 전에 중단
/usr/sbin/danted -V -f /etc/danted-random.conf


echo "[6/7] Creating systemd service..."

cat > /etc/systemd/system/random-socks5.service <<'EOF'
[Unit]
Description=Random Authenticated SOCKS5 Proxy
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=/usr/sbin/danted -f /etc/danted-random.conf
Restart=always
RestartSec=2

# 너무 빨리 재시작 제한에 걸리는 것 방지
StartLimitBurst=0

[Install]
WantedBy=multi-user.target
EOF

# StartLimitBurst는 일반적으로 Unit 옵션이므로 별도 drop-in으로 확실하게 지정
mkdir -p /etc/systemd/system/random-socks5.service.d

cat > /etc/systemd/system/random-socks5.service.d/restart.conf <<'EOF'
[Unit]
StartLimitIntervalSec=0

[Service]
Restart=always
RestartSec=2
EOF


echo "[7/7] Saving credentials and starting service..."

cat > /etc/random-socks5.env <<EOF
SOCKS_PORT=${SOCKS_PORT}
SOCKS_USER=${SOCKS_USER}
SOCKS_PASS=${SOCKS_PASS}
EXT_IF=${EXT_IF}
EOF

chmod 600 /etc/random-socks5.env

cat > /root/socks5-credentials.txt <<EOF
SOCKS5 PORT     : ${SOCKS_PORT}
SOCKS5 USERNAME : ${SOCKS_USER}
SOCKS5 PASSWORD : ${SOCKS_PASS}
EOF

chmod 600 /root/socks5-credentials.txt

systemctl daemon-reload
systemctl enable random-socks5.service
systemctl restart random-socks5.service

sleep 1

echo
echo "=================================================="
echo " SOCKS5 INSTALLED"
echo "=================================================="
echo
echo "PORT     : ${SOCKS_PORT}"
echo "USERNAME : ${SOCKS_USER}"
echo "PASSWORD : ${SOCKS_PASS}"
echo
echo "INTERFACE: ${EXT_IF}"
echo
echo "Credentials saved:"
echo "  /root/socks5-credentials.txt"
echo
echo "Service:"
echo "  systemctl status random-socks5"
echo
echo "Logs:"
echo "  journalctl -u random-socks5 -f"
echo
echo "Listening:"
ss -ltnp | grep ":${SOCKS_PORT}" || true
echo
echo "=================================================="

if systemctl is-active --quiet random-socks5.service; then
    echo "STATUS: RUNNING"
else
    echo "STATUS: FAILED"
    echo
    journalctl -u random-socks5.service --no-pager -n 50
    exit 1
fi
