use anyhow::Result;
use rmcp::{
    handler::server::wrapper::Parameters,
    schemars,
    tool, tool_router,
    ServiceExt,
    transport::stdio,
};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

mod config;
mod installer;
mod state;
mod updater;

use config::Config;
use installer::Installer;

#[derive(Clone)]
struct CompanyMgr {
    installer: Installer,
}

impl CompanyMgr {
    fn new(cfg: &Config) -> Self {
        Self {
            installer: Installer::new(cfg),
        }
    }
}

#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
struct InstallPackageParams {
    /// 패키지 이름 (예: "design/webcash")
    package: String,
    /// 설치 위치: "workspace" (현재 프로젝트) 또는 "global" (~/.claude)
    #[serde(default = "default_target")]
    #[schemars(default = "default_target")]
    target: String,
}

fn default_target() -> String {
    "workspace".to_string()
}

#[tool_router(server_handler)]
impl CompanyMgr {
    #[tool(description = "설치 가능한 표준 패키지 목록을 조회합니다")]
    async fn list_packages(&self) -> String {
        self.installer
            .list_packages()
            .await
            .unwrap_or_else(|e| format!("오류: {e}"))
    }

    #[tool(description = "표준 패키지를 설치합니다. 사용 예: package='design/webcash', target='workspace'|'global'")]
    async fn install_package(
        &self,
        Parameters(InstallPackageParams { package, target }): Parameters<InstallPackageParams>,
    ) -> String {
        self.installer
            .install_package(&package, &target)
            .await
            .unwrap_or_else(|e| format!("오류: {e}"))
    }

    #[tool(description = "현재 설치된 패키지 목록과 버전을 조회합니다")]
    async fn status(&self) -> String {
        self.installer
            .status()
            .await
            .unwrap_or_else(|e| format!("오류: {e}"))
    }

    #[tool(description = "설치된 모든 패키지를 최신 버전으로 업데이트합니다")]
    async fn update_all(&self) -> String {
        self.installer
            .update_all()
            .await
            .unwrap_or_else(|e| format!("오류: {e}"))
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::fmt::layer()
                .with_writer(std::io::stderr)
                .with_ansi(false),
        )
        .with(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive(tracing::Level::INFO.into()),
        )
        .init();

    tracing::info!("company-mgr v{} starting", env!("CARGO_PKG_VERSION"));

    // 구멍 3: 셀프 업데이트 (타임아웃 + 실패 시 조용히 계속)
    updater::check_and_update().await;

    let cfg = Config::load();
    let server = CompanyMgr::new(&cfg).serve(stdio()).await?;
    server.waiting().await?;
    Ok(())
}
