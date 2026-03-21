use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ConsumerId {
    BeagleOperator,
    DarwinResearch,
}

impl ConsumerId {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::BeagleOperator => "beagle-operator",
            Self::DarwinResearch => "darwin-research",
        }
    }

    pub fn from_header(value: &str) -> Option<Self> {
        match value.trim().to_ascii_lowercase().as_str() {
            "beagle-operator" => Some(Self::BeagleOperator),
            "darwin-research" => Some(Self::DarwinResearch),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConsumerIdentity {
    pub id: String,
    pub lane: String,
    pub description: String,
    pub allowed_profiles: Vec<String>,
    pub allow_workspace_plane: bool,
    pub allow_hpc_control: bool,
    pub allow_hpc_submit: bool,
    pub allow_hpc_read: bool,
    pub allow_bridge_read: bool,
    pub allow_bridge_execute: bool,
}

impl ConsumerIdentity {
    pub fn allows_profile(&self, profile_id: &str) -> bool {
        self.allowed_profiles.iter().any(|allowed| allowed == profile_id)
    }

    pub fn ensure_workspace_plane(&self) -> Result<(), String> {
        if self.allow_workspace_plane {
            Ok(())
        } else {
            Err(format!("consumer {} is not allowed to use the workspace plane", self.id))
        }
    }

    pub fn ensure_hpc_control(&self) -> Result<(), String> {
        if self.allow_hpc_control {
            Ok(())
        } else {
            Err(format!("consumer {} is not allowed to use the HPC control surface", self.id))
        }
    }

    pub fn ensure_hpc_submit(&self, profile_id: &str) -> Result<(), String> {
        if !self.allow_hpc_submit {
            return Err(format!("consumer {} is not allowed to submit HPC jobs", self.id));
        }
        if !self.allows_profile(profile_id) {
            return Err(format!(
                "consumer {} is not allowed to submit profile {}",
                self.id, profile_id
            ));
        }
        Ok(())
    }

    pub fn ensure_hpc_read(&self) -> Result<(), String> {
        if self.allow_hpc_read {
            Ok(())
        } else {
            Err(format!("consumer {} is not allowed to read HPC results", self.id))
        }
    }

    pub fn ensure_bridge_read(&self) -> Result<(), String> {
        if self.allow_bridge_read {
            Ok(())
        } else {
            Err(format!("consumer {} is not allowed to read bridge state", self.id))
        }
    }

    pub fn ensure_bridge_execute(&self) -> Result<(), String> {
        if self.allow_bridge_execute {
            Ok(())
        } else {
            Err(format!("consumer {} is not allowed to execute bridge actions", self.id))
        }
    }
}

pub fn consumer_identity_for_id(id: ConsumerId) -> ConsumerIdentity {
    match id {
        ConsumerId::BeagleOperator => ConsumerIdentity {
            id: id.as_str().to_string(),
            lane: "operator".to_string(),
            description:
                "Primary operator path with workspace, control-surface and bridge access."
                    .to_string(),
            allowed_profiles: vec![
                "cpu-short-v1".to_string(),
                "cpu-batch-v1".to_string(),
                "gpu-single-v1".to_string(),
            ],
            allow_workspace_plane: true,
            allow_hpc_control: true,
            allow_hpc_submit: true,
            allow_hpc_read: true,
            allow_bridge_read: true,
            allow_bridge_execute: true,
        },
        ConsumerId::DarwinResearch => ConsumerIdentity {
            id: id.as_str().to_string(),
            lane: "research".to_string(),
            description:
                "Controlled research path limited to approved CPU profiles through the shared Beagle surface."
                    .to_string(),
            allowed_profiles: vec!["cpu-short-v1".to_string(), "cpu-batch-v1".to_string()],
            allow_workspace_plane: false,
            allow_hpc_control: false,
            allow_hpc_submit: true,
            allow_hpc_read: true,
            allow_bridge_read: false,
            allow_bridge_execute: false,
        },
    }
}

pub fn available_consumers() -> Vec<ConsumerIdentity> {
    vec![
        consumer_identity_for_id(ConsumerId::BeagleOperator),
        consumer_identity_for_id(ConsumerId::DarwinResearch),
    ]
}
