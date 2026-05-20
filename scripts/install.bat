@echo off
:: =============================================================================
::  company-mgr 설치 스크립트 — Windows
::  사용법: 더블클릭 또는 cmd에서 실행 (관리자 권한 불필요)
::  사전 요건: Windows 10 이상, Claude Code CLI 설치됨
:: =============================================================================

title company-mgr 설치

:: ── 배포 시 이 두 줄을 실제 값으로 변경하세요 ─────────────────────────────────
set GITHUB_REPO=MyLittleLuckyDog/company-mgr
set TOOLING_SERVER=http://TOOLING_SERVER_IP:8080
:: ─────────────────────────────────────────────────────────────────────────────

set INSTALL_DIR=%USERPROFILE%\.company
set BIN_PATH=%INSTALL_DIR%\company-mgr.exe
set CFG_PATH=%INSTALL_DIR%\config.json

echo ========================================
echo   company-mgr 설치 (Windows/amd64)
echo ========================================
echo.

:: PowerShell로 전체 설치 진행 (실행 정책 우회 포함)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$repo = '%GITHUB_REPO%';" ^
    "$server = '%TOOLING_SERVER%';" ^
    "$dir = '%INSTALL_DIR%';" ^
    "$bin = '%BIN_PATH%';" ^
    "$cfg = '%CFG_PATH%';" ^
    "$asset = 'company-mgr-windows-amd64.exe';" ^
    "" ^
    "Write-Host '1/4  GitHub 최신 릴리스 확인 중...';" ^
    "try {" ^
    "    $r = Invoke-RestMethod -Uri \"https://api.github.com/repos/$repo/releases/latest\" -Headers @{'User-Agent'='company-mgr-installer'};" ^
    "} catch { Write-Host \"[오류] GitHub API 연결 실패: $_\" -ForegroundColor Red; exit 1 };" ^
    "$a = $r.assets | Where-Object { $_.name -eq $asset };" ^
    "if (-not $a) { Write-Host \"[오류] $asset asset을 찾을 수 없습니다.\" -ForegroundColor Red; exit 1 };" ^
    "" ^
    "Write-Host \"2/4  바이너리 다운로드 중... ($($r.tag_name))\";" ^
    "New-Item -ItemType Directory -Force -Path $dir | Out-Null;" ^
    "try {" ^
    "    Invoke-WebRequest -Uri $a.browser_download_url -OutFile $bin -UseBasicParsing;" ^
    "} catch { Write-Host \"[오류] 다운로드 실패: $_\" -ForegroundColor Red; exit 1 };" ^
    "Write-Host \"  OK: $bin\" -ForegroundColor Green;" ^
    "" ^
    "Write-Host '3/4  설정 파일 생성 중...';" ^
    "@{ tooling_server = $server; tooling_token = '' } | ConvertTo-Json | Set-Content -Path $cfg -Encoding UTF8;" ^
    "Write-Host \"  OK: $cfg\" -ForegroundColor Green;" ^
    "" ^
    "Write-Host '4/4  Claude Code MCP 등록 중...';" ^
    "$claude = Get-Command claude -ErrorAction SilentlyContinue;" ^
    "if ($claude) {" ^
    "    & claude mcp remove company -s user 2>$null;" ^
    "    & claude mcp add -s user company $bin;" ^
    "    Write-Host '  OK: MCP 등록 완료 (user scope)' -ForegroundColor Green;" ^
    "} else {" ^
    "    Write-Host '  [주의] claude CLI를 찾을 수 없습니다.' -ForegroundColor Yellow;" ^
    "    Write-Host \"  아래 명령을 직접 실행하세요:\" -ForegroundColor Yellow;" ^
    "    Write-Host \"  claude mcp add -s user company $bin\" -ForegroundColor Yellow;" ^
    "};" ^
    "" ^
    "Write-Host '';" ^
    "Write-Host '========================================' -ForegroundColor Green;" ^
    "Write-Host '  설치 완료!' -ForegroundColor Green;" ^
    "Write-Host '========================================' -ForegroundColor Green;" ^
    "Write-Host '';" ^
    "Write-Host \"  바이너리  : $bin\";" ^
    "Write-Host \"  설정 파일 : $cfg\";" ^
    "Write-Host \"  Tooling   : $server\";" ^
    "Write-Host '';" ^
    "Write-Host '  -> Claude Code를 재시작하면 company MCP가 자동 연결됩니다.';" ^
    "Write-Host '  -> 연결 확인: claude mcp list';"

if errorlevel 1 (
    echo.
    echo [오류] 설치 중 문제가 발생했습니다.
    echo 위 오류 메시지를 확인하거나 담당자에게 문의하세요.
    pause
    exit /b 1
)

echo.
pause
