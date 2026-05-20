# company-mgr 설치 가이드

Claude Code에서 사내 표준(디자인·보안·성능)을 자동으로 적용해주는 MCP 도구입니다.  
한 번 설치하면 이후 업데이트는 자동으로 처리됩니다.

---

## 사전 요건

| 항목 | 최소 버전 |
|------|----------|
| Claude Code CLI | 최신 버전 |
| macOS | 12 Monterey 이상 |
| Windows | 10 (22H2) 이상 |
| 사내 네트워크 | 접속 상태 (Tooling Server 연결 필요) |

---

## 설치 방법

### macOS

터미널을 열고 아래 명령을 실행합니다.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/MyLittleLuckyDog/company-mgr/master/scripts/install.sh)
```

> **또는** `scripts/install.sh` 파일을 받아서 직접 실행:
> ```bash
> bash install.sh
> ```

---

### Windows

`scripts/install.bat` 파일을 **더블클릭**합니다.

- 관리자 권한 불필요
- PowerShell 실행 정책 변경 불필요 (내부적으로 우회 처리)

> **주의**: Windows Defender가 경고를 표시할 수 있습니다.  
> "추가 정보" → "실행"을 클릭하면 됩니다.

---

## 설치 후 확인

Claude Code를 **재시작**한 뒤 아래 명령으로 연결을 확인합니다.

```bash
claude mcp list
```

`company: ✓ Connected` 가 표시되면 설치 완료입니다.

---

## 설치되는 파일

```
~/.company/
├── company-mgr        # MCP 바이너리 (Windows: company-mgr.exe)
├── config.json        # Tooling Server 주소·토큰
└── installed.json     # 설치된 표준 패키지 목록 (자동 생성)
```

**config.json 내용:**
```json
{
  "tooling_server": "http://[서버주소]:8080",
  "tooling_token": ""
}
```

---

## 사용 방법

설치 후 Claude Code에서 자연어로 명령합니다.

| 발화 예시 | 동작 |
|----------|------|
| "어떤 표준 패키지 있어?" | 설치 가능한 패키지 목록 조회 |
| "webcash 디자인 설정해줘" | 현재 프로젝트에 디자인 표준 설치 |
| "webcash 디자인 글로벌로 설치해줘" | 모든 프로젝트에 공통 적용 |
| "뭐 설치돼 있어?" | 설치 현황 확인 |
| "업데이트해줘" | 설치된 패준 파일 최신화 |

### 설치 위치 (`target`)

| target | 경로 | 적용 범위 |
|--------|------|----------|
| `workspace` (기본값) | `{현재 프로젝트}/.claude/` | 현재 프로젝트만 |
| `global` | `~/.claude/` | 모든 프로젝트 |

---

## 자동 업데이트

Claude Code 시작 시 GitHub에서 새 버전을 자동으로 확인합니다.  
새 버전이 있으면 자동으로 교체 후 재시작됩니다 — 별도 작업 불필요.

- 확인 타임아웃: 5초 (네트워크 불안정 시 무시하고 정상 기동)
- 업데이트 실패 시: 경고 로그만 남기고 계속 동작

---

## 문제 해결

### `company: ✗ Failed to connect`

1. `~/.company/company-mgr` 파일이 존재하는지 확인
2. 실행 권한 확인: `ls -la ~/.company/company-mgr`
3. 수동 실행 테스트: `~/.company/company-mgr` (에러 메시지 확인)
4. 재등록: `claude mcp add -s user company ~/.company/company-mgr`

### macOS — "개발자를 확인할 수 없음" 경고

시스템 설정 → 개인정보 보호 및 보안 → **"확인 없이 열기"** 클릭  
이후 정상적으로 실행됩니다.

### Tooling Server에 연결되지 않음

사내 네트워크 접속 상태를 확인하세요.  
VPN이 필요한 경우 VPN 연결 후 Claude Code를 재시작합니다.

---

## 제거 방법

```bash
# MCP 등록 해제
claude mcp remove company -s user

# 파일 삭제
rm -rf ~/.company
```

---

문의: [담당자 Slack 채널 또는 이메일]
