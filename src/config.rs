use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Config {
    pub tooling_server: String,
    #[serde(default)]
    pub tooling_token: String,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            tooling_server: "http://localhost:18080".to_string(),
            tooling_token: String::new(),
        }
    }
}

impl Config {
    pub fn config_path() -> PathBuf {
        let home = std::env::var("HOME")
            .or_else(|_| std::env::var("USERPROFILE"))
            .unwrap_or_else(|_| ".".to_string());
        PathBuf::from(home).join(".company").join("config.json")
    }

    /// 우선순위: 환경변수 > config.json > 기본값
    pub fn load() -> Self {
        if let Ok(url) = std::env::var("COMPANY_TOOLING_SERVER") {
            return Self {
                tooling_server: url,
                tooling_token: std::env::var("COMPANY_TOOLING_TOKEN").unwrap_or_default(),
            };
        }

        let path = Self::config_path();
        if path.exists() {
            if let Ok(content) = std::fs::read_to_string(&path) {
                if let Ok(cfg) = serde_json::from_str::<Self>(&content) {
                    return cfg;
                }
            }
        }

        let default = Self::default();
        tracing::warn!(
            "~/.company/config.json 없음 — 기본값 사용: {}",
            default.tooling_server
        );
        default
    }
}
