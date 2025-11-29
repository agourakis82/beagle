//! Workflow definition types for AutoGen Studio-inspired UI
//!
//! Provides JSON-serializable workflow definitions for visual workflow building
//! and declarative agent composition.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

// ============================================================================
// Workflow Definition
// ============================================================================

/// Complete workflow definition (JSON-serializable for UI)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkflowDefinition {
    /// Schema version
    #[serde(default = "default_version")]
    pub version: String,

    /// Unique workflow ID
    #[serde(default = "generate_id")]
    pub id: String,

    /// Workflow name
    pub name: String,

    /// Description of what the workflow does
    pub description: Option<String>,

    /// Team of agents
    pub team: TeamDefinition,

    /// Tools available to agents
    #[serde(default)]
    pub tools: Vec<ToolDefinition>,

    /// Execution flow
    pub flow: FlowDefinition,

    /// Custom metadata
    #[serde(default)]
    pub metadata: HashMap<String, serde_json::Value>,

    /// Tags for categorization
    #[serde(default)]
    pub tags: Vec<String>,
}

fn default_version() -> String {
    "1.0".to_string()
}

fn generate_id() -> String {
    Uuid::new_v4().to_string()
}

impl WorkflowDefinition {
    /// Create a new workflow
    pub fn new(name: impl Into<String>) -> Self {
        Self {
            version: default_version(),
            id: generate_id(),
            name: name.into(),
            description: None,
            team: TeamDefinition::default(),
            tools: Vec::new(),
            flow: FlowDefinition::default(),
            metadata: HashMap::new(),
            tags: Vec::new(),
        }
    }

    /// Validate the workflow definition
    pub fn validate(&self) -> Result<(), WorkflowValidationError> {
        // Check for duplicate agent IDs
        let mut seen_ids = std::collections::HashSet::new();
        for agent in &self.team.agents {
            if !seen_ids.insert(&agent.id) {
                return Err(WorkflowValidationError::DuplicateAgentId(agent.id.clone()));
            }
        }

        // Check that all flow steps reference valid agents
        for step in &self.flow.steps {
            if !self.team.agents.iter().any(|a| a.id == step.agent) {
                return Err(WorkflowValidationError::InvalidAgentReference(
                    step.agent.clone(),
                ));
            }

            // Check tool references
            if let Some(ref tools) = step.tools {
                for tool_id in tools {
                    if !self.tools.iter().any(|t| &t.id == tool_id) {
                        return Err(WorkflowValidationError::InvalidToolReference(
                            tool_id.clone(),
                        ));
                    }
                }
            }
        }

        // Check termination condition is valid
        self.team.termination.validate()?;

        Ok(())
    }

    /// Get agent by ID
    pub fn get_agent(&self, agent_id: &str) -> Option<&AgentDefinition> {
        self.team.agents.iter().find(|a| a.id == agent_id)
    }

    /// Get tool by ID
    pub fn get_tool(&self, tool_id: &str) -> Option<&ToolDefinition> {
        self.tools.iter().find(|t| t.id == tool_id)
    }

    /// Add an agent to the team
    pub fn with_agent(mut self, agent: AgentDefinition) -> Self {
        self.team.agents.push(agent);
        self
    }

    /// Add a tool
    pub fn with_tool(mut self, tool: ToolDefinition) -> Self {
        self.tools.push(tool);
        self
    }

    /// Add a flow step
    pub fn with_step(mut self, step: FlowStep) -> Self {
        self.flow.steps.push(step);
        self
    }
}

/// Workflow validation errors
#[derive(Debug, Clone, thiserror::Error)]
pub enum WorkflowValidationError {
    #[error("Duplicate agent ID: {0}")]
    DuplicateAgentId(String),

    #[error("Invalid agent reference: {0}")]
    InvalidAgentReference(String),

    #[error("Invalid tool reference: {0}")]
    InvalidToolReference(String),

    #[error("Invalid termination condition: {0}")]
    InvalidTermination(String),

    #[error("Empty workflow: no steps defined")]
    EmptyWorkflow,

    #[error("Circular dependency detected")]
    CircularDependency,
}

// ============================================================================
// Team Definition
// ============================================================================

/// Definition of an agent team
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TeamDefinition {
    /// Team name
    pub name: String,

    /// Agents in the team
    #[serde(default)]
    pub agents: Vec<AgentDefinition>,

    /// Termination condition
    #[serde(default)]
    pub termination: TerminationConfig,
}

impl Default for TeamDefinition {
    fn default() -> Self {
        Self {
            name: "Default Team".to_string(),
            agents: Vec::new(),
            termination: TerminationConfig::default(),
        }
    }
}

/// Definition of an agent
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentDefinition {
    /// Unique agent ID within workflow
    pub id: String,

    /// Agent type (e.g., "research_specialist", "writer", "critic")
    #[serde(rename = "type")]
    pub agent_type: String,

    /// Human-readable name
    pub name: Option<String>,

    /// Agent description
    pub description: Option<String>,

    /// Capabilities this agent has
    #[serde(default)]
    pub capabilities: Vec<String>,

    /// Model configuration
    #[serde(default)]
    pub model_config: ModelConfig,

    /// System prompt override
    pub system_prompt: Option<String>,

    /// Tools this agent can use
    #[serde(default)]
    pub tools: Vec<String>,

    /// Custom agent parameters
    #[serde(default)]
    pub parameters: HashMap<String, serde_json::Value>,
}

impl AgentDefinition {
    /// Create a new agent definition
    pub fn new(id: impl Into<String>, agent_type: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            agent_type: agent_type.into(),
            name: None,
            description: None,
            capabilities: Vec::new(),
            model_config: ModelConfig::default(),
            system_prompt: None,
            tools: Vec::new(),
            parameters: HashMap::new(),
        }
    }

    /// Create an ATHENA agent
    pub fn athena() -> Self {
        Self::new("athena", "research_specialist")
            .with_name("ATHENA")
            .with_description("Research accuracy and literature specialist")
            .with_capabilities(vec!["research", "analysis", "citation"])
            .with_model_tier("premium")
            .with_phd_level(true)
    }

    /// Create a HERMES agent
    pub fn hermes() -> Self {
        Self::new("hermes", "writer")
            .with_name("HERMES")
            .with_description("Writing synthesis and editing specialist")
            .with_capabilities(vec!["writing", "synthesis", "editing"])
            .with_model_tier("standard")
    }

    /// Create an ARGOS agent
    pub fn argos() -> Self {
        Self::new("argos", "critic")
            .with_name("ARGOS")
            .with_description("Critical review and bias detection specialist")
            .with_capabilities(vec!["analysis", "critique", "validation"])
            .with_model_tier("premium")
            .with_high_bias_risk(true)
    }

    /// Create a Judge agent
    pub fn judge() -> Self {
        Self::new("judge", "arbitrator")
            .with_name("Judge")
            .with_description("Final arbitration and decision making")
            .with_capabilities(vec!["arbitration", "decision", "synthesis"])
            .with_model_tier("premium")
            .with_critical_section(true)
    }

    // Builder methods
    pub fn with_name(mut self, name: impl Into<String>) -> Self {
        self.name = Some(name.into());
        self
    }

    pub fn with_description(mut self, desc: impl Into<String>) -> Self {
        self.description = Some(desc.into());
        self
    }

    pub fn with_capabilities(mut self, caps: Vec<impl Into<String>>) -> Self {
        self.capabilities = caps.into_iter().map(|c| c.into()).collect();
        self
    }

    pub fn with_system_prompt(mut self, prompt: impl Into<String>) -> Self {
        self.system_prompt = Some(prompt.into());
        self
    }

    pub fn with_model_tier(mut self, tier: impl Into<String>) -> Self {
        self.model_config.tier = tier.into();
        self
    }

    pub fn with_phd_level(mut self, required: bool) -> Self {
        self.model_config.requires_phd_level = Some(required);
        self
    }

    pub fn with_high_bias_risk(mut self, risk: bool) -> Self {
        self.model_config.high_bias_risk = Some(risk);
        self
    }

    pub fn with_critical_section(mut self, critical: bool) -> Self {
        self.model_config.critical_section = Some(critical);
        self
    }
}

/// Model configuration for an agent
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelConfig {
    /// Model tier (e.g., "standard", "premium", "specialized")
    #[serde(default = "default_tier")]
    pub tier: String,

    /// Requires PhD-level reasoning
    pub requires_phd_level: Option<bool>,

    /// High bias risk (needs anti-bias measures)
    pub high_bias_risk: Option<bool>,

    /// Critical section (final decisions)
    pub critical_section: Option<bool>,

    /// Maximum tokens for response
    pub max_tokens: Option<usize>,

    /// Temperature for sampling
    pub temperature: Option<f32>,

    /// Specific model name override
    pub model_name: Option<String>,
}

fn default_tier() -> String {
    "standard".to_string()
}

impl Default for ModelConfig {
    fn default() -> Self {
        Self {
            tier: default_tier(),
            requires_phd_level: None,
            high_bias_risk: None,
            critical_section: None,
            max_tokens: None,
            temperature: None,
            model_name: None,
        }
    }
}

// ============================================================================
// Tool Definition
// ============================================================================

/// Definition of a tool available to agents
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolDefinition {
    /// Unique tool ID
    pub id: String,

    /// Tool name
    pub name: String,

    /// Tool description
    pub description: Option<String>,

    /// Tool type
    #[serde(rename = "type")]
    pub tool_type: ToolType,

    /// Tool configuration
    #[serde(default)]
    pub config: HashMap<String, serde_json::Value>,

    /// Parameter schema (JSON Schema)
    pub parameters: Option<serde_json::Value>,
}

/// Type of tool
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ToolType {
    /// External API
    Api,
    /// Database query
    Database,
    /// File operation
    File,
    /// Code execution
    Code,
    /// Search
    Search,
    /// Custom/plugin
    Custom,
}

impl ToolDefinition {
    /// Create a PubMed search tool
    pub fn pubmed_search() -> Self {
        Self {
            id: "pubmed_search".to_string(),
            name: "PubMed Search".to_string(),
            description: Some("Search PubMed for scientific literature".to_string()),
            tool_type: ToolType::Api,
            config: HashMap::from([
                (
                    "endpoint".to_string(),
                    serde_json::json!("https://eutils.ncbi.nlm.nih.gov/entrez/eutils/"),
                ),
                ("rate_limit".to_string(), serde_json::json!(3)),
            ]),
            parameters: Some(serde_json::json!({
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Search query"},
                    "max_results": {"type": "integer", "default": 10}
                },
                "required": ["query"]
            })),
        }
    }

    /// Create an arXiv search tool
    pub fn arxiv_search() -> Self {
        Self {
            id: "arxiv_search".to_string(),
            name: "arXiv Search".to_string(),
            description: Some("Search arXiv for preprints".to_string()),
            tool_type: ToolType::Api,
            config: HashMap::from([(
                "endpoint".to_string(),
                serde_json::json!("https://export.arxiv.org/api/"),
            )]),
            parameters: Some(serde_json::json!({
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Search query"},
                    "max_results": {"type": "integer", "default": 10},
                    "sort_by": {"type": "string", "enum": ["relevance", "lastUpdatedDate", "submittedDate"]}
                },
                "required": ["query"]
            })),
        }
    }
}

// ============================================================================
// Flow Definition
// ============================================================================

/// Definition of execution flow
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FlowDefinition {
    /// Flow type
    #[serde(rename = "type", default)]
    pub flow_type: FlowType,

    /// Steps in the flow
    #[serde(default)]
    pub steps: Vec<FlowStep>,

    /// Error handling strategy
    #[serde(default)]
    pub error_handling: ErrorHandling,
}

impl Default for FlowDefinition {
    fn default() -> Self {
        Self {
            flow_type: FlowType::Sequential,
            steps: Vec::new(),
            error_handling: ErrorHandling::default(),
        }
    }
}

/// Type of execution flow
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "snake_case")]
pub enum FlowType {
    /// Steps execute one after another
    #[default]
    Sequential,
    /// Steps can execute in parallel
    Parallel,
    /// Steps execute based on conditions
    Conditional,
    /// Steps can loop
    Loop,
    /// Dynamic routing based on content
    Router,
}

/// A step in the flow
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FlowStep {
    /// Step ID (optional, auto-generated if not provided)
    pub id: Option<String>,

    /// Agent to execute this step
    pub agent: String,

    /// Action to perform
    pub action: String,

    /// Input sources (can reference outputs from other steps)
    pub input: Option<Vec<String>>,

    /// Output name for this step's result
    pub output: Option<String>,

    /// Condition for execution (for conditional flows)
    pub condition: Option<String>,

    /// Tools to use in this step
    pub tools: Option<Vec<String>>,

    /// Timeout in milliseconds
    pub timeout_ms: Option<u64>,

    /// Retry configuration
    pub retry: Option<RetryConfig>,
}

impl FlowStep {
    /// Create a new flow step
    pub fn new(agent: impl Into<String>, action: impl Into<String>) -> Self {
        Self {
            id: None,
            agent: agent.into(),
            action: action.into(),
            input: None,
            output: None,
            condition: None,
            tools: None,
            timeout_ms: None,
            retry: None,
        }
    }

    pub fn with_id(mut self, id: impl Into<String>) -> Self {
        self.id = Some(id.into());
        self
    }

    pub fn with_input(mut self, inputs: Vec<impl Into<String>>) -> Self {
        self.input = Some(inputs.into_iter().map(|i| i.into()).collect());
        self
    }

    pub fn with_output(mut self, output: impl Into<String>) -> Self {
        self.output = Some(output.into());
        self
    }

    pub fn with_condition(mut self, condition: impl Into<String>) -> Self {
        self.condition = Some(condition.into());
        self
    }

    pub fn with_tools(mut self, tools: Vec<impl Into<String>>) -> Self {
        self.tools = Some(tools.into_iter().map(|t| t.into()).collect());
        self
    }
}

/// Retry configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RetryConfig {
    /// Maximum number of retries
    pub max_retries: u32,
    /// Delay between retries in milliseconds
    pub delay_ms: u64,
    /// Exponential backoff factor
    pub backoff_factor: Option<f32>,
}

impl Default for RetryConfig {
    fn default() -> Self {
        Self {
            max_retries: 3,
            delay_ms: 1000,
            backoff_factor: Some(2.0),
        }
    }
}

/// Error handling strategy
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ErrorHandling {
    /// Strategy for handling errors
    #[serde(default)]
    pub strategy: ErrorStrategy,
    /// Fallback step to execute on error
    pub fallback_step: Option<String>,
}

/// Error handling strategy
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "snake_case")]
pub enum ErrorStrategy {
    /// Stop execution on error
    #[default]
    Stop,
    /// Continue to next step
    Continue,
    /// Retry the failed step
    Retry,
    /// Execute fallback
    Fallback,
}

// ============================================================================
// Termination Configuration
// ============================================================================

/// Configuration for workflow termination
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminationConfig {
    /// Termination type
    #[serde(rename = "type", default)]
    pub termination_type: TerminationType,

    /// Maximum rounds/iterations
    pub max_rounds: Option<u32>,

    /// Minimum score to accept
    pub min_score: Option<f32>,

    /// Maximum execution time in seconds
    pub max_time_secs: Option<u64>,

    /// Custom termination condition expression
    pub condition: Option<String>,
}

impl Default for TerminationConfig {
    fn default() -> Self {
        Self {
            termination_type: TerminationType::AllStepsComplete,
            max_rounds: Some(10),
            min_score: None,
            max_time_secs: Some(300),
            condition: None,
        }
    }
}

impl TerminationConfig {
    pub fn validate(&self) -> Result<(), WorkflowValidationError> {
        if let Some(max_rounds) = self.max_rounds {
            if max_rounds == 0 {
                return Err(WorkflowValidationError::InvalidTermination(
                    "max_rounds must be > 0".to_string(),
                ));
            }
        }
        if let Some(min_score) = self.min_score {
            if !(0.0..=1.0).contains(&min_score) {
                return Err(WorkflowValidationError::InvalidTermination(
                    "min_score must be between 0 and 1".to_string(),
                ));
            }
        }
        Ok(())
    }
}

/// Type of termination condition
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
#[serde(rename_all = "snake_case")]
pub enum TerminationType {
    /// Stop when all steps complete
    #[default]
    AllStepsComplete,
    /// Stop when any agent signals done
    AgentSignal,
    /// Stop when score threshold reached
    ScoreThreshold,
    /// Stop when consensus reached
    Consensus,
    /// Stop when judge makes decision
    JudgeDecision,
    /// Custom condition
    Custom,
}

// ============================================================================
// Workflow Templates
// ============================================================================

impl WorkflowDefinition {
    /// Create a Triad workflow template
    pub fn triad_template() -> Self {
        Self::new("Research Triad")
            .with_agent(AgentDefinition::athena())
            .with_agent(AgentDefinition::hermes())
            .with_agent(AgentDefinition::argos())
            .with_agent(AgentDefinition::judge())
            .with_tool(ToolDefinition::pubmed_search())
            .with_tool(ToolDefinition::arxiv_search())
            .with_step(
                FlowStep::new("athena", "review")
                    .with_input(vec!["draft"])
                    .with_output("athena_feedback"),
            )
            .with_step(
                FlowStep::new("hermes", "rewrite")
                    .with_input(vec!["draft", "athena_feedback"])
                    .with_output("hermes_draft"),
            )
            .with_step(
                FlowStep::new("argos", "critique")
                    .with_input(vec!["draft", "hermes_draft", "athena_feedback"])
                    .with_output("argos_critique"),
            )
            .with_step(
                FlowStep::new("judge", "arbitrate")
                    .with_input(vec![
                        "draft",
                        "hermes_draft",
                        "athena_feedback",
                        "argos_critique",
                    ])
                    .with_output("final_draft"),
            )
    }

    /// Create a simple Q&A workflow
    pub fn qa_template() -> Self {
        let mut workflow = Self::new("Q&A Workflow");
        workflow.description = Some("Simple question answering workflow".to_string());
        workflow.team = TeamDefinition {
            name: "QA Team".to_string(),
            agents: vec![AgentDefinition::new("qa_agent", "assistant")
                .with_name("QA Agent")
                .with_capabilities(vec!["answering", "research"])],
            termination: TerminationConfig {
                termination_type: TerminationType::AllStepsComplete,
                max_rounds: Some(1),
                ..Default::default()
            },
        };
        workflow.flow = FlowDefinition {
            flow_type: FlowType::Sequential,
            steps: vec![FlowStep::new("qa_agent", "answer")
                .with_input(vec!["question"])
                .with_output("answer")],
            error_handling: ErrorHandling::default(),
        };
        workflow
    }

    /// Create a research workflow
    pub fn research_template() -> Self {
        let mut workflow = Self::new("Research Pipeline");
        workflow.description = Some("Deep research with multiple sources".to_string());
        workflow.team = TeamDefinition {
            name: "Research Team".to_string(),
            agents: vec![
                AgentDefinition::new("researcher", "research_specialist")
                    .with_name("Researcher")
                    .with_capabilities(vec!["search", "analysis"]),
                AgentDefinition::new("synthesizer", "writer")
                    .with_name("Synthesizer")
                    .with_capabilities(vec!["writing", "synthesis"]),
            ],
            termination: TerminationConfig::default(),
        };
        workflow.tools = vec![
            ToolDefinition::pubmed_search(),
            ToolDefinition::arxiv_search(),
        ];
        workflow.flow = FlowDefinition {
            flow_type: FlowType::Sequential,
            steps: vec![
                FlowStep::new("researcher", "search")
                    .with_input(vec!["query"])
                    .with_output("search_results")
                    .with_tools(vec!["pubmed_search", "arxiv_search"]),
                FlowStep::new("researcher", "analyze")
                    .with_input(vec!["search_results"])
                    .with_output("analysis"),
                FlowStep::new("synthesizer", "synthesize")
                    .with_input(vec!["analysis", "query"])
                    .with_output("final_report"),
            ],
            error_handling: ErrorHandling::default(),
        };
        workflow
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_workflow_creation() {
        let workflow = WorkflowDefinition::new("Test Workflow");
        assert_eq!(workflow.name, "Test Workflow");
        assert_eq!(workflow.version, "1.0");
    }

    #[test]
    fn test_triad_template() {
        let workflow = WorkflowDefinition::triad_template();

        assert_eq!(workflow.team.agents.len(), 4);
        assert_eq!(workflow.flow.steps.len(), 4);
        assert_eq!(workflow.tools.len(), 2);

        assert!(workflow.validate().is_ok());
    }

    #[test]
    fn test_agent_definitions() {
        let athena = AgentDefinition::athena();
        assert_eq!(athena.id, "athena");
        assert_eq!(athena.model_config.tier, "premium");
        assert_eq!(athena.model_config.requires_phd_level, Some(true));

        let argos = AgentDefinition::argos();
        assert_eq!(argos.model_config.high_bias_risk, Some(true));
    }

    #[test]
    fn test_validation_duplicate_agent() {
        let mut workflow = WorkflowDefinition::new("Test");
        workflow.team.agents = vec![
            AgentDefinition::new("agent1", "type"),
            AgentDefinition::new("agent1", "type"), // Duplicate
        ];

        assert!(matches!(
            workflow.validate(),
            Err(WorkflowValidationError::DuplicateAgentId(_))
        ));
    }

    #[test]
    fn test_validation_invalid_agent_ref() {
        let mut workflow = WorkflowDefinition::new("Test");
        workflow.team.agents = vec![AgentDefinition::new("agent1", "type")];
        workflow.flow.steps = vec![FlowStep::new("nonexistent", "action")];

        assert!(matches!(
            workflow.validate(),
            Err(WorkflowValidationError::InvalidAgentReference(_))
        ));
    }

    #[test]
    fn test_serialization() {
        let workflow = WorkflowDefinition::triad_template();
        let json = serde_json::to_string_pretty(&workflow).unwrap();

        assert!(json.contains("athena"));
        assert!(json.contains("HERMES"));
        assert!(json.contains("pubmed_search"));

        // Deserialize back
        let parsed: WorkflowDefinition = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.team.agents.len(), 4);
    }

    #[test]
    fn test_flow_step_builder() {
        let step = FlowStep::new("agent1", "process")
            .with_id("step_1")
            .with_input(vec!["input1", "input2"])
            .with_output("result")
            .with_tools(vec!["tool1"]);

        assert_eq!(step.id, Some("step_1".to_string()));
        assert_eq!(
            step.input,
            Some(vec!["input1".to_string(), "input2".to_string()])
        );
        assert_eq!(step.output, Some("result".to_string()));
    }
}
