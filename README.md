# Debian SOCKS5 Proxy

빈 Debian 서버에 인증이 필요한 Dante SOCKS5 프록시를 설치합니다. 저장소를 clone하지 않고 GitHub Personal Access Token(PAT)으로 스크립트 하나만 다운로드해서 실행할 수 있습니다.

## 동작

| 스크립트 | 기능 |
| --- | --- |
| `setup.sh` | 설치, 자동 시작 등록, 접속 정보 출력 |
| `reset.sh` | 사용자명 유지, 포트·비밀번호 변경, 서비스 재시작 |
| `uninstall.sh` | 서비스·설정·접속 정보 파일·전용 계정 삭제 |

- 사용자명: `proxyauthuser`
- 포트: `20000–60000` 범위에서 사용 중이지 않은 TCP 포트 랜덤 선택
- 비밀번호: `openssl rand -hex 16`으로 생성한 32자리 문자열(128비트 난수)
- 서비스: `socks5-proxy.service`
- 설정: `/etc/socks5-proxy.conf`
- 접속 정보: `/root/socks5-credentials.txt`, `/etc/socks5-proxy.env` (권한 `600`)
- URL: `socks5://proxyauthuser:PASSWORD@SERVER_IP:PORT`

공인 IPv4는 `https://api.ipify.org`에서 조회합니다. 조회에 실패하면 URL에 `YOUR_SERVER_IP`가 표시되므로 실제 서버 주소로 바꾸세요. NAT 환경에서는 조회된 주소가 실제 인바운드 접속 주소인지 확인해야 합니다.

## 사전 준비

- systemd를 사용하는 Debian 서버와 root 권한(또는 `sudo` 권한)
- GitHub 및 Debian 패키지 저장소에 접근 가능한 네트워크
- `curl`, CA 인증서

최소 Debian 서버에서 root로 접속했다면 먼저 실행하세요.

```bash
apt-get update && apt-get install -y curl ca-certificates
```

일반 사용자라면 두 명령 앞에 각각 `sudo`를 붙이세요.

## GitHub PAT 발급

발급 페이지: <https://github.com/settings/personal-access-tokens/new>

GitHub **Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token**에서도 접근할 수 있습니다.

| 항목 | 권장 설정 |
| --- | --- |
| Token name | `socks5-installer` |
| Expiration | 필요한 기간만큼 짧게 |
| Resource owner | `solixcorp` |
| Repository access | **Only select repositories** |
| 선택할 저장소 | `socks5-proxy-bootstrap` |
| Repository permissions → Contents | **Read-only** |

`Metadata: Read-only`는 자동 포함됩니다. 다른 권한은 필요하지 않습니다. 조직 정책에 따라 관리자 승인이 필요하거나 발급이 제한될 수 있습니다. `solixcorp`가 보이지 않으면 조직 멤버십과 토큰 정책을 확인하세요.

생성 직후 표시되는 토큰을 복사하세요. 토큰을 README나 저장소에 넣지 마세요.

## 권장: 실행 시 PAT를 입력하는 한 줄 명령어

아래 명령어를 **Bash 터미널**에 붙여 넣으면 `GitHub PAT:` 입력창이 나옵니다. 토큰을 붙여 넣고 Enter를 누르세요. 입력한 토큰은 화면에 표시되지 않습니다.

명령어 자체에 토큰이 없으므로 셸 히스토리에 토큰을 직접 남기지 않습니다. 인증 헤더는 표준 입력으로 curl에 전달하여 curl 실행 인자에도 토큰을 넣지 않습니다. 다운로드 실패 시 실행하지 않고, 종료 시 임시 파일을 제거합니다. 일반 사용자로 실행하면 별도로 sudo 비밀번호가 필요할 수 있습니다.

### 설치

```bash
( set -euo pipefail; umask 077; read -rsp 'GitHub PAT: ' PAT; echo; FILE=$(mktemp); trap 'rm -f "$FILE"; unset PAT' EXIT; printf 'header = "Authorization: Bearer %s"\n' "$PAT" | curl --config - -fsS -H 'Accept: application/vnd.github.raw+json' 'https://api.github.com/repos/solixcorp/socks5-proxy-bootstrap/contents/setup.sh?ref=main' -o "$FILE"; unset PAT; if (( EUID == 0 )); then bash "$FILE"; else sudo bash "$FILE"; fi )
```

설치 스크립트를 재실행하면 포트와 비밀번호가 새로 생성됩니다. 기존 `danted.service`와 이전 버전의 `random-socks5.service`는 중단됩니다. 다른 Dante 서비스를 운영 중인 서버에는 주의해서 사용하세요.

### 포트·비밀번호 리셋

```bash
( set -euo pipefail; umask 077; read -rsp 'GitHub PAT: ' PAT; echo; FILE=$(mktemp); trap 'rm -f "$FILE"; unset PAT' EXIT; printf 'header = "Authorization: Bearer %s"\n' "$PAT" | curl --config - -fsS -H 'Accept: application/vnd.github.raw+json' 'https://api.github.com/repos/solixcorp/socks5-proxy-bootstrap/contents/reset.sh?ref=main' -o "$FILE"; unset PAT; if (( EUID == 0 )); then bash "$FILE"; else sudo bash "$FILE"; fi )
```

`proxyauthuser`와 기존 접근 규칙은 유지합니다. 새 포트와 비밀번호를 생성하고 접속 정보 파일을 갱신합니다. 적용 중 실패하면 기존 설정과 비밀번호 해시 복원을 시도합니다.

**리셋 후 클라이언트 설정과 방화벽·클라우드 보안 그룹의 허용 포트도 변경하세요.**

### 삭제

```bash
( set -euo pipefail; umask 077; read -rsp 'GitHub PAT: ' PAT; echo; FILE=$(mktemp); trap 'rm -f "$FILE"; unset PAT' EXIT; printf 'header = "Authorization: Bearer %s"\n' "$PAT" | curl --config - -fsS -H 'Accept: application/vnd.github.raw+json' 'https://api.github.com/repos/solixcorp/socks5-proxy-bootstrap/contents/uninstall.sh?ref=main' -o "$FILE"; unset PAT; if (( EUID == 0 )); then bash "$FILE"; else sudo bash "$FILE"; fi )
```

확인 질문 없이 서비스를 중단하고 관련 파일과 `proxyauthuser` 계정을 삭제합니다. 패키지, 홈 디렉터리, 방화벽·보안 그룹 규칙은 삭제하지 않습니다. 이전 버전의 파일과 계정은 별도로 정리해야 합니다.

## 선택: PAT를 미리 포함하는 버전

추가 입력 없이 실행하려면 아래 `YOUR_GITHUB_TOKEN`을 토큰으로 바꿀 수 있습니다. **이 방식은 토큰이 셸 히스토리·터미널 기록에 남을 수 있으므로 권장하지 않습니다. 실제 토큰이 들어간 명령어를 공유하거나 커밋하지 마세요.**

```bash
( set -euo pipefail; umask 077; FILE=$(mktemp); trap 'rm -f "$FILE"' EXIT; printf '%s\n' 'header = "Authorization: Bearer YOUR_GITHUB_TOKEN"' | curl --config - -fsS -H 'Accept: application/vnd.github.raw+json' 'https://api.github.com/repos/solixcorp/socks5-proxy-bootstrap/contents/setup.sh?ref=main' -o "$FILE"; if (( EUID == 0 )); then bash "$FILE"; else sudo bash "$FILE"; fi )
```

리셋·삭제는 URL의 `setup.sh`를 각각 `reset.sh`, `uninstall.sh`로 바꾸세요.

## 출력 예시

아래 주소와 비밀번호는 예시입니다.

```text
PORT     : 38472
USERNAME : proxyauthuser
PASSWORD : 7b8e2c904a1f63d5e0b92a6c18f743dd
URL      : socks5://proxyauthuser:7b8e2c904a1f63d5e0b92a6c18f743dd@203.0.113.10:38472
```

```bash
# 접속 정보 확인
sudo cat /root/socks5-credentials.txt

# 서비스 상태
sudo systemctl status socks5-proxy

# 서비스 로그
sudo journalctl -u socks5-proxy -f
```

## 보안 및 운영 주의사항

- 원격 코드를 root로 실행합니다. 신뢰할 수 있는 저장소에서만 실행하세요. 명령어는 `main`의 최신 파일을 사용합니다. 검토한 버전을 고정하려면 URL의 `ref=main`을 `ref=커밋SHA`로 바꾸세요.
- 토큰 입력 시 셸의 디버그 추적(`set -x`)을 사용하지 마세요. PAT는 제한된 권한과 짧은 만료 기간으로 발급하고 필요 없으면 폐기하세요.
- SOCKS5 사용자명·비밀번호 인증은 클라이언트와 프록시 사이의 암호화를 제공하지 않습니다. 안전한 전송이 필요하면 VPN이나 SSH 터널을 사용하세요.
- 랜덤 포트는 보안 경계가 아닙니다. 가능한 경우 방화벽·보안 그룹에서 접속할 출발지 IP만 허용하세요. 스크립트는 방화벽을 자동 설정하지 않습니다.
- 서버의 모든 IPv4 인터페이스에서 접속을 받습니다. 인증된 사용자는 서버가 접근 가능한 내부망에도 요청할 수 있습니다. 필요하면 목적지 접근 규칙을 제한하세요.
- UDP를 사용할 경우 TCP 리스닝 포트 개방만으로 충분하지 않을 수 있습니다.
- 접속 정보 파일과 출력 URL에는 평문 비밀번호가 포함됩니다. root 권한, 서버 백업, 터미널 기록에 주의하세요. 저장된 접속 정보는 서비스 동작에 필수는 아니지만 현재 리셋 스크립트는 두 파일이 존재해야 실행됩니다.
- 서비스 실행 및 포트 리스닝 확인은 실제 외부 접속·인증 성공을 보장하지 않습니다. 설치 후 클라이언트에서 확인하세요.

## 원격 실행 전 반영

새 파일과 이름 변경은 GitHub에 push되어야 다운로드할 수 있습니다. 로컬에서만 변경한 파일은 위 명령어로 받을 수 없습니다.
