#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo bash $0"
    exit 1
fi

SERVICE="socks5-proxy.service"
SOCKS_USER="proxyauthuser"

# Fail rather than removing configuration underneath a running proxy.
if [[ -f "/etc/systemd/system/${SERVICE}" ]] ||
    systemctl cat "$SERVICE" >/dev/null 2>&1; then
    systemctl stop "$SERVICE"
    systemctl disable "$SERVICE"
fi

rm -f -- "/etc/systemd/system/${SERVICE}"
rm -rf -- "/etc/systemd/system/${SERVICE}.d"
systemctl daemon-reload
systemctl reset-failed "$SERVICE" 2>/dev/null || true

rm -f -- /etc/socks5-proxy.conf /etc/socks5-proxy.env /root/socks5-credentials.txt

# Keep home directories and never force-delete an account with running processes.
if id "$SOCKS_USER" >/dev/null 2>&1; then
    if ! userdel "$SOCKS_USER"; then
        echo "ERROR: Service and files removed, but account ${SOCKS_USER} could not be deleted."
        echo "Check running processes and remove the account manually."
        exit 1
    fi
fi

echo "SOCKS5 UNINSTALLED"
echo "Removed service, configuration, saved credentials, and ${SOCKS_USER} account."
echo "Packages and firewall/security group rules were left unchanged."
