**English** | [한국어](README-KO.md)

# Debian SOCKS5 Proxy

Installs an authenticated Dante SOCKS5 proxy on a fresh Debian server. The scripts are downloaded from a public repository and executed directly, so no git clone or GitHub auth token is required.

## Overview

| Script | Function |
| --- | --- |
| `setup.sh` | Installs the proxy, enables auto-start, prints connection details |
| `reset.sh` | Keeps the username, changes the port and password, restarts the service |
| `uninstall.sh` | Removes the service, config, credential files, and dedicated account |

- Username: `proxyauthuser`
- Port: a random unused TCP port in the `20000–60000` range
- Password: a 32-character string generated with `openssl rand -hex 16` (128 bits of randomness)
- Service: `socks5-proxy.service`
- Config: `/etc/socks5-proxy.conf`
- Install method: installs the `dante-server` package if available in apt; otherwise builds the official Dante 1.4.4 source after SHA-256 verification
- Source install path: `/opt/socks5-proxy` (for environments without the package, such as Debian 13 trixie)

- Credentials: `/root/socks5-credentials.txt`, `/etc/socks5-proxy.env` (permissions `600`)
- URL: `socks5://proxyauthuser:PASSWORD@SERVER_IP:PORT`

A source install additionally installs `build-essential` and may take a while depending on server performance. Repositories from other Debian releases are never mixed in.

The public IPv4 address is looked up via `https://api.ipify.org`. If the lookup fails, the URL shows `YOUR_SERVER_IP`; replace it with the actual server address. Behind NAT, verify that the detected address is the one actually reachable for inbound connections.

## Prerequisites

- A Debian server running systemd, with root access (or `sudo` privileges)
- Network access to GitHub and the Debian package repositories
- `curl` and CA certificates

If you are logged in as root on a minimal Debian server, run this first:

```bash
apt-get update && apt-get install -y curl ca-certificates
```

As a regular user, prefix each of the two commands with `sudo`.

## One-line Commands

Paste the commands below into a **Bash terminal**. GitHub `blob` pages are HTML, so the `raw.githubusercontent.com` URLs, which serve the raw file contents, are used instead.

The downloaded content is executed immediately with root privileges, without any token prompt. If you are logged in as root, use `bash` instead of `sudo bash`. These commands use Bash's `pipefail` so that download errors are reflected in the exit status, but execution may begin before the download completes.

### Install

```bash
( set -o pipefail; curl -fsSL https://raw.githubusercontent.com/solixcorp/socks5-proxy-bootstrap/main/setup.sh | sudo bash )
```

Re-running the setup script generates a new port and password. Any existing `danted.service` and the legacy `random-socks5.service` from earlier versions will be stopped. Use with caution on servers running other Dante services.

### Reset Port and Password

```bash
( set -o pipefail; curl -fsSL https://raw.githubusercontent.com/solixcorp/socks5-proxy-bootstrap/main/reset.sh | sudo bash )
```

`proxyauthuser` and the existing access rules are kept. A new port and password are generated and the credential files are updated. If applying the change fails, the script attempts to restore the previous config and password hash.

**After a reset, also update your client settings and the allowed port in your firewall and cloud security groups.**

### Uninstall

```bash
( set -o pipefail; curl -fsSL https://raw.githubusercontent.com/solixcorp/socks5-proxy-bootstrap/main/uninstall.sh | sudo bash )
```

Stops the service and removes the related files and the `proxyauthuser` account without asking for confirmation. For source installs, `/opt/socks5-proxy` is also removed. apt packages (including build tools), home directories, and firewall/security group rules are not removed. Files and accounts from earlier versions must be cleaned up separately.

## Example Output

The address and password below are examples.

```text
PORT     : 38472
USERNAME : proxyauthuser
PASSWORD : 7b8e2c904a1f63d5e0b92a6c18f743dd
URL      : socks5://proxyauthuser:7b8e2c904a1f63d5e0b92a6c18f743dd@203.0.113.10:38472
```

```bash
# Show connection details
sudo cat /root/socks5-credentials.txt

# Service status
sudo systemctl status socks5-proxy

# Service logs
sudo journalctl -u socks5-proxy -f
```

## Security and Operational Notes

- This runs remote code as root. Only run it from a repository you trust. The commands use the latest files on `main`; to pin a reviewed version, replace `/main/` in the URL with `/<commit-SHA>/`.
- SOCKS5 username/password authentication does not encrypt traffic between the client and the proxy. Use a VPN or SSH tunnel if you need secure transport.
- A random port is not a security boundary. Where possible, allow only the source IPs that need access in your firewall or security groups. The scripts do not configure the firewall automatically.
- The proxy accepts connections on all IPv4 interfaces of the server. Authenticated users can also reach internal networks accessible from the server. Restrict destination access rules if needed.
- If you use UDP, opening only the TCP listening port may not be sufficient.
- The credential files and the printed URL contain the password in plain text. Be careful with root access, server backups, and terminal history. The saved credentials are not required for the service to run, but the reset script currently requires both files to exist.
- A running service and a listening port do not guarantee that external connections and authentication actually succeed. Verify from a client after installation.

## Publish Before Running Remotely

The commands above only work if the repository is public and the files have been pushed to GitHub. Changes made only locally will not be downloaded.
