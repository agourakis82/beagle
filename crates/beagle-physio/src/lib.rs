//! BEAGLE Physiological Metrics - HRV, Heart Rate, Sleep Integration
//! Integra métricas do Apple Watch no loop metacognitivo

pub mod speed_control;

use serde::{Deserialize, Serialize};
use tracing::{info, warn};
use anyhow::Result;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PhysiologicalState {
    pub hrv_ms: f64,
    pub heart_rate: f64,
    pub sleep_hours: f64,
    pub flow_state: FlowState,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum FlowState {
    Flow,
    Stress,
    Unknown,
}

impl PhysiologicalState {
    pub fn new(hrv_ms: f64, heart_rate: f64, sleep_hours: f64) -> Self {
        let flow_state = if hrv_ms > 80.0 && sleep_hours >= 7.0 {
            FlowState::Flow
        } else if hrv_ms < 50.0 {
            FlowState::Stress
        } else {
            FlowState::Unknown
        };
        
        Self {
            hrv_ms,
            heart_rate,
            sleep_hours,
            flow_state,
        }
    }
    
    /// Ajusta velocidade do adversarial loop baseado no estado fisiológico
    pub fn should_accelerate(&self) -> bool {
        matches!(self.flow_state, FlowState::Flow)
    }
    
    /// Pausa o loop se estiver em stress
    pub fn should_pause(&self) -> bool {
        matches!(self.flow_state, FlowState::Stress)
    }
}

/// Recebe métricas do Apple Watch e integra no loop
pub async fn integrate_physio_metrics(
    hrv_ms: f64,
    heart_rate: f64,
    sleep_hours: f64,
) -> Result<PhysiologicalState> {
    let state = PhysiologicalState::new(hrv_ms, heart_rate, sleep_hours);
    
    info!(
        "📊 Estado fisiológico: HRV={:.1}ms, HR={:.0}bpm, Sleep={:.1}h — {:?}",
        state.hrv_ms,
        state.heart_rate,
        state.sleep_hours,
        state.flow_state
    );
    
    if state.should_accelerate() {
        info!("🚀 Acelerando adversarial loop (FLOW state)");
    } else if state.should_pause() {
        warn!("⏸️  Pausando adversarial loop (STRESS state)");
    }
    
    Ok(state)
}

