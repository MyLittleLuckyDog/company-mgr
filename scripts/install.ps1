# company-mgr 설치 스크립트 (Windows)
#
# 실행 방법 (PowerShell 실행 정책 우회):
#   powershell -ExecutionPolicy Bypass -File install.ps1
#
# 또는 관리자 권한 없이 현재 사용자에 한해 허용:
#   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
#   .\install.ps1

# ── 사내 배포 시 이 값을 실제 서버 주소로 변경하세요 ──────────────────────────
$GITHUB_REPO   = "MyLittleLuckyDog/company-mgr"
$TOOLING_SERVER = if ($env:COMPANY_TOOLING_SERVER) { $env:COMPANY_TOOLING_SERVER } else { "http://TOOLING_SERVER_IP:8080" }
# ─────────────────────────────────────────────────────────────────────────────

$INSTALL_DIR = "$env:USERPROFILE\.company"
$ASSET       = "company-mgr-windows-amd64.exe"

Write-Host "========================================"
Write-Host "  company-mgr 설치 (Windows/amd64)"
Write-Host "========================================"

# ── GitHub 최신 릴리스 조회 ────────────────────────────────────────────────────
Write-Host "GitHub 최신 릴리스 확인 중..."
try {
    $release = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/$GITHUB_REPO/releases/latest" `
        -Headers @{ "User-Agent" = "company-mgr-installer" }
} catch {
    Write-Error "GitHub API 연결 실패: $_"
    exit 1
}

$asset = $release.assets | Where-Object { $_.name -eq $ASSET }
if (-not $asset) {
    Write-Error "릴리스 asset을 찾을 수 없습니다: $ASSET"
    Write-Host "https://github.com/$GITHUB_REPO/releases 에서 직접 확인해주세요."
    exit 1
}

# ── 바이너리 다운로드 ──────────────────────────────────────────────────────────
Write-Host "다운로드 중: $($asset.browser_download_url)"
New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null
Invoke-WebRequest -Uri $asset.browser_download_url `
    -OutFile "$INSTALL_DIR\company-mgr.exe" `
    -UseBasicParsing

# ── config.json 생성 ──────────────────────────────────────────────────────────
Write-Host "설정 파일 생성 중..."
$config = [ordered]@{
    tooling_server = $TOOLING_SERVER
    tooling_token  = ""
}
$config | ConvertTo-Json | Set-Content -Path "$INSTALL_DIR\config.json" -Encoding UTF8

# ── MCP 서버 등록 ────────────────────────────────────────────────────────────
Write-Host "Claude Code MCP 등록 중..."
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if ($claudeCmd) {
    & claude mcp add -s user company "$INSTALL_DIR\company-mgr.exe"
    Write-Host "v MCP 등록 완료"
} else {
    Write-Warning "claude CLI를 찾을 수 없습니다."
    Write-Host "  설치 후 아래 명령을 직접 실행하세요:"
    Write-Host "  claude mcp add -s user company `"$INSTALL_DIR\company-mgr.exe`""
}

Write-Host ""
Write-Host "========================================"
Write-Host "  설치 완료!"
Write-Host "========================================"
Write-Host "  바이너리: $INSTALL_DIR\company-mgr.exe"
Write-Host "  설정:    $INSTALL_DIR\config.json"
Write-Host ""
Write-Host "Claude Code를 재시작하면 'company' MCP가 연결됩니다."
Write-Host "연결 확인: claude mcp list"
