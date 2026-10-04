#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# Debian SOCKS5 Proxy Installer
# - Random port
# - Fixed username: proxyauthuser
# - Random password
# - SOCKS5 username/password authentication
# - systemd auto start
# - Restart forever on crash
# ==========================================================

if [[ $EUID -ne 0 ]]; then
    echo "Run as root:"
    echo "  sudo bash $0"
    exit 1
fi

# 비밀번호 파일은 생성 시점부터 root만 읽을 수 있도록 설정
umask 077
export DEBIAN_FRONTEND=noninteractive

echo "[1/7] Installing packages..."
apt-get update
apt-get install -y openssl iproute2 curl ca-certificates

if apt-cache policy dante-server | grep -E 'Candidate: .*[0-9]' >/dev/null; then
    apt-get install -y dante-server
    DANTED_BIN="/usr/sbin/danted"
else
    echo "dante-server is unavailable; building official Dante 1.4.4 source..."
    apt-get install -y build-essential
    BUILD_DIR="$(mktemp -d)"
    trap 'rm -rf -- "$BUILD_DIR"' EXIT
    curl -fsSL --retry 3 https://www.inet.no/dante/files/dante-1.4.4.tar.gz \
        -o "$BUILD_DIR/dante.tar.gz"
    printf '%s  %s\n' \
        '1973c7732f1f9f0a4c0ccf2c1ce462c7c25060b25643ea90f9b98f53a813faec' \
        "$BUILD_DIR/dante.tar.gz" | sha256sum --check -
    tar -xzf "$BUILD_DIR/dante.tar.gz" -C "$BUILD_DIR"
    (
        cd "$BUILD_DIR/dante-1.4.4"
        # Build only the server, in an isolated prefix owned by this installer.
        ./configure --prefix=/opt/socks5-proxy --disable-client --disable-preload
        make -j "$(nproc)"
        make install
    )
    DANTED_BIN="/opt/socks5-proxy/sbin/sockd"
    # umask 077 also affects make install; allow the unprivileged daemon to traverse.
    chmod 755 /opt/socks5-proxy /opt/socks5-proxy/sbin "$DANTED_BIN"
    rm -rf -- "$BUILD_DIR"
    trap - EXIT
fi

if [[ ! -x "$DANTED_BIN" ]]; then
    echo "ERROR: Dante server executable not found: $DANTED_BIN"
    exit 1
fi

# 기존 기본 danted 서비스와 충돌 방지
systemctl disable --now danted.service 2>/dev/null || true
# 이전 버전 스크립트의 서비스가 있으면 중단
systemctl disable --now random-socks5.service 2>/dev/null || true


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

# 공인 IPv4 조회 실패 시에도 설치는 계속 진행
PUBLIC_IP="$(curl -4 --fail --silent --show-error --connect-timeout 5 --max-time 10 https://api.ipify.org 2>/dev/null || true)"
if [[ ! "${PUBLIC_IP}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    PUBLIC_IP="YOUR_SERVER_IP"
    echo "WARNING: Could not detect public IPv4. Replace YOUR_SERVER_IP in the SOCKS5 URL."
fi


echo "[3/7] Generating random SOCKS5 port..."

while true; do
    SOCKS_PORT="$(shuf -i 20000-60000 -n 1)"

    if ! ss -ltnH | awk '{print $4}' | grep -E ":${SOCKS_PORT}$" >/dev/null; then
        break
    fi
done


echo "[4/7] Setting up proxy credentials..."

SOCKS_USER="proxyauthuser"
SOCKS_PASS="$(openssl rand -hex 16)"
SOCKS_URL="socks5://${SOCKS_USER}:${SOCKS_PASS}@${PUBLIC_IP}:${SOCKS_PORT}"

# SOCKS 인증 전용 로컬 계정: 재실행 시 기존 계정 사용
if ! id "${SOCKS_USER}" >/dev/null 2>&1; then
    useradd \
        --no-create-home \
        --shell /usr/sbin/nologin \
        "${SOCKS_USER}"
fi

echo "${SOCKS_USER}:${SOCKS_PASS}" | chpasswd


echo "[5/7] Writing Dante configuration..."

cat > /etc/socks5-proxy.conf <<EOF
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
    user: ${SOCKS_USER}
    log: error
}
EOF

chmod 600 /etc/socks5-proxy.conf

# 설정 오류가 있으면 서비스 등록 전에 중단
"$DANTED_BIN" -V -f /etc/socks5-proxy.conf


echo "[6/7] Creating systemd service..."

cat > /etc/systemd/system/socks5-proxy.service <<EOF
[Unit]
Description=SOCKS5 Proxy
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=${DANTED_BIN} -f /etc/socks5-proxy.conf
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

chmod 644 /etc/systemd/system/socks5-proxy.service


echo "[7/7] Saving credentials and starting service..."

cat > /etc/socks5-proxy.env <<EOF
SOCKS_PORT=${SOCKS_PORT}
SOCKS_USER=${SOCKS_USER}
SOCKS_PASS=${SOCKS_PASS}
EXT_IF=${EXT_IF}
SOCKS_URL=${SOCKS_URL}
EOF

chmod 600 /etc/socks5-proxy.env

cat > /root/socks5-credentials.txt <<EOF
SOCKS5 PORT     : ${SOCKS_PORT}
SOCKS5 USERNAME : ${SOCKS_USER}
SOCKS5 PASSWORD : ${SOCKS_PASS}
SOCKS5 URL      : ${SOCKS_URL}
EOF

chmod 600 /root/socks5-credentials.txt

systemctl daemon-reload
systemctl enable socks5-proxy.service
systemctl restart socks5-proxy.service

sleep 1

echo
echo "=================================================="
echo " SOCKS5 INSTALLED"
echo "=================================================="
echo
echo "PORT     : ${SOCKS_PORT}"
echo "USERNAME : ${SOCKS_USER}"
echo "PASSWORD : ${SOCKS_PASS}"
echo "URL      : ${SOCKS_URL}"
echo
echo "INTERFACE: ${EXT_IF}"
echo
echo "Credentials saved:"
echo "  /root/socks5-credentials.txt"
echo
echo "Service:"
echo "  systemctl status socks5-proxy"
echo
echo "Logs:"
echo "  journalctl -u socks5-proxy -f"
echo
echo "Listening:"
ss -ltnp | grep ":${SOCKS_PORT}" || true
echo
echo "=================================================="

if systemctl is-active --quiet socks5-proxy.service; then
    echo "STATUS: RUNNING"
else
    echo "STATUS: FAILED"
    echo
    journalctl -u socks5-proxy.service --no-pager -n 50
    exit 1
fi
