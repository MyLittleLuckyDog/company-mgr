#!/usr/bin/env bash
# =============================================================================
#  company-mgr 설치 스크립트 — macOS / Linux
#  사용법: bash install.sh
#  사전 요건: curl, python3, claude CLI
# =============================================================================

set -euo pipefail

# ── 배포 시 이 두 줄을 실제 값으로 변경하세요 ─────────────────────────────────
GITHUB_REPO="MyLittleLuckyDog/company-mgr"
TOOLING_SERVER="${COMPANY_TOOLING_SERVER:-http://TOOLING_SERVER_IP:8080}"
# ─────────────────────────────────────────────────────────────────────────────

INSTALL_DIR="$HOME/.company"
BIN_PATH="$INSTALL_DIR/company-mgr"
CFG_PATH="$INSTALL_DIR/config.json"

# ── 색상 출력 ─────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
err()  { echo -e "${RED}✗${NC} $*" >&2; exit 1; }

echo "========================================"
echo "  company-mgr 설치"
echo "========================================"
echo ""

# ── OS / ARCH 감지 ─────────────────────────────────────────────────────────────
RAW_OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$RAW_OS" in
  darwin) OS="darwin" ;;
  linux)  OS="linux"  ;;
  *)      err "지원하지 않는 OS: $RAW_OS (macOS / Linux만 지원)" ;;
esac

RAW_ARCH=$(uname -m)
case "$RAW_ARCH" in
  x86_64)        ARCH="amd64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *)             err "지원하지 않는 아키텍처: $RAW_ARCH" ;;
esac

ASSET="company-mgr-${OS}-${ARCH}"
echo "플랫폼: ${OS}/${ARCH} → ${ASSET}"
echo ""

# ── 사전 요건 확인 ─────────────────────────────────────────────────────────────
command -v curl    &>/dev/null || err "curl이 필요합니다. 설치 후 다시 실행하세요."
command -v python3 &>/dev/null || err "python3이 필요합니다. 설치 후 다시 실행하세요."

# ── GitHub 최신 릴리스 URL 조회 ────────────────────────────────────────────────
echo "1/4  GitHub 최신 릴리스 확인 중..."
API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
DOWNLOAD_URL=$(
  curl -sf "$API_URL" \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
tag  = data.get('tag_name', '?')
matches = [
    a['browser_download_url']
    for a in data.get('assets', [])
    if a['name'] == '${ASSET}'
]
if matches:
    print(matches[0])
else:
    import sys; print(f'ERROR: {tag} 릴리스에 ${ASSET} asset이 없습니다', file=sys.stderr); sys.exit(1)
" || true
)

[ -z "$DOWNLOAD_URL" ] && err "릴리스 asset을 찾을 수 없습니다. https://github.com/${GITHUB_REPO}/releases 확인"

# ── 바이너리 다운로드 ──────────────────────────────────────────────────────────
echo "2/4  바이너리 다운로드 중..."
mkdir -p "$INSTALL_DIR"
curl -fL --progress-bar "$DOWNLOAD_URL" -o "$BIN_PATH"
chmod +x "$BIN_PATH"

# macOS: quarantine 속성 제거 (curl 다운로드는 보통 불필요, 방어적 실행)
if [ "$OS" = "darwin" ]; then
  xattr -d com.apple.quarantine "$BIN_PATH" 2>/dev/null || true
fi
ok "바이너리: $BIN_PATH"

# ── config.json 생성 ──────────────────────────────────────────────────────────
echo "3/4  설정 파일 생성 중..."
cat > "$CFG_PATH" <<EOF
{
  "tooling_server": "${TOOLING_SERVER}",
  "tooling_token": ""
}
EOF
ok "설정 파일: $CFG_PATH"

# ── Claude Code MCP 등록 ──────────────────────────────────────────────────────
echo "4/4  Claude Code MCP 등록 중..."
if command -v claude &>/dev/null; then
  # 기존 등록이 있으면 제거 후 재등록
  claude mcp remove company -s user 2>/dev/null || true
  claude mcp add -s user company "$BIN_PATH"
  ok "MCP 등록 완료 (user scope)"
else
  warn "claude CLI를 찾을 수 없습니다. 아래 명령을 직접 실행하세요:"
  echo "     claude mcp add -s user company \"$BIN_PATH\""
fi

# ── 완료 ──────────────────────────────────────────────────────────────────────
echo ""
echo "========================================"
ok "설치 완료!"
echo "========================================"
echo ""
echo "  바이너리  : $BIN_PATH"
echo "  설정 파일 : $CFG_PATH"
echo "  Tooling   : $TOOLING_SERVER"
echo ""
echo "  → Claude Code를 재시작하면 'company' MCP가 자동으로 연결됩니다."
echo "  → 연결 확인: claude mcp list"
echo ""
