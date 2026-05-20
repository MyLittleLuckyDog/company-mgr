use anyhow::{Context, Result};
use std::path::PathBuf;

use crate::config::Config;
use crate::state::{InstalledPackage, State};

#[derive(Clone)]
pub struct Installer {
    server_url: String,
    token: String,
    client: reqwest::Client,
}

impl Installer {
    pub fn new(cfg: &Config) -> Self {
        tracing::info!("tooling server: {}", cfg.tooling_server);
        Self {
            server_url: cfg.tooling_server.clone(),
            token: cfg.tooling_token.clone(),
            client: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(30))
                .build()
                .expect("reqwest client"),
        }
    }

    pub async fn list_packages(&self) -> Result<String> {
        let url = format!("{}/version", self.server_url);
        let resp: serde_json::Value = self
            .client
            .get(&url)
            .send()
            .await
            .with_context(|| format!("tooling server 연결 실패: {url}"))?
            .json()
            .await?;

        let packages = resp
            .get("packages")
            .and_then(|p| p.as_object())
            .map(|obj| {
                obj.iter()
                    .map(|(k, v)| format!("  {k}: {v}"))
                    .collect::<Vec<_>>()
                    .join("\n")
            })
            .unwrap_or_else(|| "  (패키지 없음)".to_string());

        Ok(format!("설치 가능한 패키지:\n{packages}"))
    }

    pub async fn install_package(&self, package: &str, target: &str) -> Result<String> {
        let (domain, system) = parse_package(package)?;

        let (claude_dir, claude_md_path, design_ref) = resolve_paths(target)?;

        // 디렉토리 생성
        tokio::fs::create_dir_all(&claude_dir).await?;

        // DESIGN.md 다운로드
        let design_url = format!("{}/standards/{domain}/{system}/DESIGN.md", self.server_url);
        let design_content = self
            .download_file(&design_url)
            .await
            .with_context(|| format!("DESIGN.md 다운로드 실패: {design_url}"))?;

        let design_path = claude_dir.join("DESIGN.md");
        tokio::fs::write(&design_path, &design_content).await?;

        // SKILL.md 다운로드
        let skill_url = format!("{}/standards/{domain}/{system}/SKILL.md", self.server_url);
        let skill_content = self.download_file(&skill_url).await.ok();

        let skill_path = if let Some(content) = skill_content {
            let skill_dir = claude_dir
                .join("skills")
                .join(format!("{system}-{domain}"));
            tokio::fs::create_dir_all(&skill_dir).await?;
            let path = skill_dir.join("SKILL.md");
            tokio::fs::write(&path, content).await?;
            Some(path)
        } else {
            tracing::warn!("SKILL.md 없음 (선택사항) — 건너뜀");
            None
        };

        // CLAUDE.md에 참조 라인 추가
        self.update_claude_md(&claude_md_path, &design_ref).await?;

        // 버전 기록
        let version = self
            .get_package_version(package)
            .await
            .unwrap_or_else(|_| "unknown".to_string());

        let today = chrono::Utc::now().format("%Y-%m-%d").to_string();
        let mut state = State::load()?;
        state.packages.insert(
            package.to_string(),
            InstalledPackage {
                version: version.clone(),
                target: target.to_string(),
                installed_at: today,
            },
        );
        state.save()?;

        let skill_line = skill_path
            .map(|p| format!("\n  SKILL.md  → {}", p.display()))
            .unwrap_or_default();

        Ok(format!(
            "✓ {package} v{version} 설치 완료 (target={target})\n  DESIGN.md → {}{skill_line}\n  CLAUDE.md → {} (참조 추가: {design_ref})",
            design_path.display(),
            claude_md_path.display(),
        ))
    }

    pub async fn status(&self) -> Result<String> {
        let state = State::load()?;
        if state.packages.is_empty() {
            return Ok("설치된 패키지가 없습니다.".to_string());
        }
        let lines: Vec<String> = state
            .packages
            .iter()
            .map(|(name, pkg)| {
                format!(
                    "  {name}: v{} ({}, {}에 설치)",
                    pkg.version, pkg.target, pkg.installed_at
                )
            })
            .collect();
        Ok(format!("설치된 패키지:\n{}", lines.join("\n")))
    }

    pub async fn update_all(&self) -> Result<String> {
        let state = State::load()?;
        if state.packages.is_empty() {
            return Ok("업데이트할 패키지가 없습니다.".to_string());
        }
        let mut results = Vec::new();
        for (name, pkg) in &state.packages {
            match self.install_package(name, &pkg.target).await {
                Ok(msg) => results.push(msg),
                Err(e) => results.push(format!("✗ {name}: {e}")),
            }
        }
        Ok(results.join("\n"))
    }

    // ── helpers ──────────────────────────────────────────────────────────────

    async fn download_file(&self, url: &str) -> Result<String> {
        let mut req = self.client.get(url);
        if !self.token.is_empty() {
            req = req.bearer_auth(&self.token);
        }
        let resp = req.send().await.with_context(|| format!("GET {url}"))?;

        if !resp.status().is_success() {
            anyhow::bail!("HTTP {}: {url}", resp.status());
        }
        Ok(resp.text().await?)
    }

    async fn update_claude_md(&self, claude_md_path: &PathBuf, reference: &str) -> Result<()> {
        let existing = if claude_md_path.exists() {
            tokio::fs::read_to_string(claude_md_path).await?
        } else {
            String::new()
        };

        if existing.lines().any(|l| l.trim() == reference) {
            return Ok(());
        }

        let content = if existing.is_empty() {
            format!("{reference}\n")
        } else {
            format!("{existing}\n{reference}\n")
        };

        if let Some(parent) = claude_md_path.parent() {
            tokio::fs::create_dir_all(parent).await?;
        }
        tokio::fs::write(claude_md_path, content).await?;
        Ok(())
    }

    async fn get_package_version(&self, package: &str) -> Result<String> {
        let url = format!("{}/version", self.server_url);
        let resp: serde_json::Value = self.client.get(&url).send().await?.json().await?;
        let version = resp["packages"][package]
            .as_str()
            .unwrap_or("0.0.0")
            .to_string();
        Ok(version)
    }
}

// ── free functions ────────────────────────────────────────────────────────────

fn parse_package(package: &str) -> Result<(&str, &str)> {
    let mut parts = package.splitn(2, '/');
    let domain = parts
        .next()
        .filter(|s| !s.is_empty())
        .with_context(|| format!("패키지 형식 오류 (예: design/webcash): {package}"))?;
    let system = parts
        .next()
        .filter(|s| !s.is_empty())
        .with_context(|| format!("패키지 형식 오류 (예: design/webcash): {package}"))?;
    Ok((domain, system))
}

/// Returns (claude_dir, claude_md_path, design_ref_line)
///
/// workspace: claude_dir = {cwd}/.claude,  CLAUDE.md = {cwd}/CLAUDE.md,  ref = @.claude/DESIGN.md
/// global:    claude_dir = ~/.claude,       CLAUDE.md = ~/.claude/CLAUDE.md, ref = @DESIGN.md
fn resolve_paths(target: &str) -> Result<(PathBuf, PathBuf, String)> {
    match target {
        "workspace" => {
            let cwd = std::env::current_dir()?;
            Ok((
                cwd.join(".claude"),
                cwd.join("CLAUDE.md"),
                "@.claude/DESIGN.md".to_string(),
            ))
        }
        "global" => {
            let home = home_dir()?;
            let claude_dir = home.join(".claude");
            Ok((
                claude_dir.clone(),
                claude_dir.join("CLAUDE.md"),
                "@DESIGN.md".to_string(),
            ))
        }
        other => anyhow::bail!(
            "target은 'workspace' 또는 'global'이어야 합니다: {other}"
        ),
    }
}

fn home_dir() -> Result<PathBuf> {
    std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .map(PathBuf::from)
        .context("홈 디렉토리를 찾을 수 없습니다")
}
