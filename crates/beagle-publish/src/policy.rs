#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PublishMode {
    DryRun,
    ManualConfirm,
    FullAuto,
}

#[derive(Debug, Clone, Copy)]
pub struct PublishPolicy {
    pub mode: PublishMode,
}

impl PublishPolicy {
    pub fn from_env() -> Self {
        let mode = std::env::var("BEAGLE_PUBLISH_MODE")
            .unwrap_or_else(|_| "DryRun".to_string())
            .to_lowercase();

        let parsed_mode = match mode.as_str() {
            "fullauto" | "full_auto" | "full-auto" => PublishMode::FullAuto,
            "manualconfirm" | "manual_confirm" | "manual-confirm" | "manual" => {
                PublishMode::ManualConfirm
            }
            _ => PublishMode::DryRun,
        };

        Self { mode: parsed_mode }
    }

    pub fn is_dry_run(&self) -> bool {
        self.mode != PublishMode::FullAuto
    }

    pub fn label(&self) -> &'static str {
        match self.mode {
            PublishMode::DryRun => "DryRun",
            PublishMode::ManualConfirm => "ManualConfirm",
            PublishMode::FullAuto => "FullAuto",
        }
    }
}
