use anyhow::{Context, Result};
use std::time::Duration;

const GITHUB_REPO: &str = "MyLittleLuckyDog/company-mgr";
const API_TIMEOUT: Duration = Duration::from_secs(5);
const DOWNLOAD_TIMEOUT: Duration = Duration::from_secs(60);
const TOTAL_TIMEOUT: Duration = Duration::from_secs(30);

/// 버전 확인 후 새 버전이 있으면 self-replace 후 exit(0).
/// 실패 시 경고 로그만 남기고 정상 기동 계속.
pub async fn check_and_update() {
    match tokio::time::timeout(TOTAL_TIMEOUT, try_update()).await {
        Ok(Ok(true)) => {
            tracing::info!("self-update 완료 — 재시작");
            std::process::exit(0);
        }
        Ok(Ok(false)) => {
            tracing::info!("최신 버전 사용 중 (v{})", env!("CARGO_PKG_VERSION"));
        }
        Ok(Err(e)) => {
            tracing::warn!("업데이트 확인 실패 (계속 기동): {e:#}");
        }
        Err(_) => {
            tracing::warn!("업데이트 확인 타임아웃 ({}s) — 계속 기동", TOTAL_TIMEOUT.as_secs());
        }
    }
}

/// true = 업데이트 적용됨 (호출자는 exit), false = 이미 최신
async fn try_update() -> Result<bool> {
    let current = semver::Version::parse(env!("CARGO_PKG_VERSION"))?;

    let client = reqwest::Client::builder()
        .user_agent(format!("company-mgr/{}", env!("CARGO_PKG_VERSION")))
        .build()?;

    let url = format!("https://api.github.com/repos/{GITHUB_REPO}/releases/latest");
    let resp: serde_json::Value = client
        .get(&url)
        .timeout(API_TIMEOUT)
        .send()
        .await
        .context("GitHub API 연결 실패")?
        .json()
        .await?;

    let tag = resp["tag_name"]
        .as_str()
        .context("tag_name 없음")?
        .trim_start_matches('v');

    let latest = semver::Version::parse(tag)?;

    if latest <= current {
        return Ok(false);
    }

    tracing::info!("새 버전 발견: v{current} → v{latest}");

    let asset_name = platform_asset_name();
    let download_url = resp["assets"]
        .as_array()
        .context("assets 없음")?
        .iter()
        .find(|a| a["name"].as_str() == Some(asset_name.as_str()))
        .and_then(|a| a["browser_download_url"].as_str())
        .with_context(|| format!("플랫폼 asset 없음: {asset_name}"))?
        .to_string();

    tracing::info!("다운로드 중: {download_url}");
    let bytes = client
        .get(&download_url)
        .timeout(DOWNLOAD_TIMEOUT)
        .send()
        .await?
        .error_for_status()?
        .bytes()
        .await?;

    self_replace(&bytes)?;
    Ok(true)
}

fn platform_asset_name() -> String {
    let os = match std::env::consts::OS {
        "macos" => "darwin",
        other => other,
    };
    let arch = match std::env::consts::ARCH {
        "x86_64" => "amd64",
        "aarch64" => "arm64",
        other => other,
    };
    let ext = if cfg!(target_os = "windows") { ".exe" } else { "" };
    format!("company-mgr-{os}-{arch}{ext}")
}

#[cfg(target_os = "windows")]
fn self_replace(new_binary: &[u8]) -> Result<()> {
    let exec_path = std::env::current_exe()?;
    // Windows: 실행 중인 파일은 삭제 불가, rename은 가능
    let old = exec_path.with_extension("old");
    std::fs::rename(&exec_path, &old)?;
    std::fs::write(&exec_path, new_binary)?;
    Ok(())
}

#[cfg(not(target_os = "windows"))]
fn self_replace(new_binary: &[u8]) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    let exec_path = std::env::current_exe()?;
    let tmp = exec_path.with_extension("tmp");
    std::fs::write(&tmp, new_binary)?;
    std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o755))?;
    // atomic rename: 실행 중 교체 가능 (Linux/macOS 모두)
    std::fs::rename(&tmp, &exec_path)?;
    // macOS: curl 경유 다운로드는 quarantine 미부착, 방어적 제거
    #[cfg(target_os = "macos")]
    let _ = std::process::Command::new("xattr")
        .args(["-d", "com.apple.quarantine", exec_path.to_str().unwrap_or("")])
        .output();
    Ok(())
}
