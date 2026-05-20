#!/usr/bin/env bash
# company-mgr 설치 스크립트 (macOS / Linux)
# 사용법: bash install.sh
# 사전 요건: curl, python3, claude CLI

set -euo pipefail

# ── 사내 배포 시 이 값을 실제 서버 주소로 변경하세요 ──────────────────────────
GITHUB_REPO="coocon/company-mgr"
TOOLING_SERVER="${COMPANY_TOOLING_SERVER:-http://TOOLING_SERVER_IP:8080}"
# ─────────────────────────────────────────────────────────────────────────────

INSTALL_DIR="$HOME/.company"

# ── OS / ARCH 감지 ─────────────────────────────────────────────────────────────
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$OS" in
  darwin) OS="darwin" ;;
  linux)  OS="linux" ;;
  *)      echo "지원하지 않는 OS: $OS" >&2; exit 1 ;;
esac

ARCH=$(uname -m)
case "$ARCH" in
  x86_64)        ARCH="amd64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *)             echo "지원하지 않는 아키텍처: $ARCH" >&2; exit 1 ;;
esac

ASSET="company-mgr-${OS}-${ARCH}"

echo "========================================"
echo "  company-mgr 설치 (${OS}/${ARCH})"
echo "========================================"

# ── GitHub 최신 릴리스 URL 조회 ────────────────────────────────────────────────
echo "GitHub 최신 릴리스 확인 중..."
DOWNLOAD_URL=$(curl -sf \
  "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
assets = data.get('assets', [])
matches = [a['browser_download_url'] for a in assets if a['name'] == '${ASSET}']
print(matches[0] if matches else '')
")

if [ -z "$DOWNLOAD_URL" ]; then
  echo "오류: 릴리스 asset을 찾을 수 없습니다: $ASSET" >&2
  echo "https://github.com/${GITHUB_REPO}/releases 에서 직접 확인해주세요." >&2
  exit 1
fi

# ── 바이너리 다운로드 ──────────────────────────────────────────────────────────
echo "다운로드 중: $DOWNLOAD_URL"
mkdir -p "$INSTALL_DIR"
curl -fL "$DOWNLOAD_URL" -o "$INSTALL_DIR/company-mgr"
chmod +x "$INSTALL_DIR/company-mgr"

# macOS quarantine 제거 (curl 경유 다운로드는 일반적으로 불필요, 방어적 실행)
if [ "$OS" = "darwin" ]; then
  xattr -d com.apple.quarantine "$INSTALL_DIR/company-mgr" 2>/dev/null || true
fi

# ── config.json 생성 ──────────────────────────────────────────────────────────
echo "설정 파일 생성 중..."
cat > "$INSTALL_DIR/config.json" <<EOF
{
  "tooling_server": "${TOOLING_SERVER}",
  "tooling_token": ""
}
EOF

# ── MCP 서버 등록 (user scope) ────────────────────────────────────────────────
echo "Claude Code MCP 등록 중..."
if command -v claude &>/dev/null; then
  claude mcp add -s user company "$INSTALL_DIR/company-mgr"
  echo "✓ MCP 등록 완료"
else
  echo "⚠ claude CLI를 찾을 수 없습니다."
  echo "  설치 후 아래 명령을 직접 실행하세요:"
  echo "  claude mcp add -s user company \"$INSTALL_DIR/company-mgr\""
fi

echo ""
echo "========================================"
echo "  설치 완료!"
echo "========================================"
echo "  바이너리: $INSTALL_DIR/company-mgr"
echo "  설정:    $INSTALL_DIR/config.json"
echo ""
echo "Claude Code를 재시작하면 'company' MCP가 연결됩니다."
echo "연결 확인: claude mcp list"
