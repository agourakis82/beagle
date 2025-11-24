//! LlmStatsRegistry - Registry de stats LLM por run_id

use beagle_llm::stats::LlmCallsStats;
use std::collections::HashMap;
use std::sync::Mutex;

/// Registry de stats por run_id
#[derive(Debug)]
pub struct LlmStatsRegistry {
    stats: Mutex<HashMap<String, LlmCallsStats>>,
}

impl LlmStatsRegistry {
    pub fn new() -> Self {
        Self {
            stats: Mutex::new(HashMap::new()),
        }
    }

    /// Obtém ou cria stats para um run_id
    pub fn get_or_create(&self, run_id: &str) -> LlmCallsStats {
        let mut map = self.stats.lock().unwrap();
        map.entry(run_id.to_string())
            .or_insert_with(LlmCallsStats::new)
            .clone()
    }

    /// Atualiza stats para um run_id
    pub fn update(&self, run_id: &str, f: impl FnOnce(&mut LlmCallsStats)) {
        let mut map = self.stats.lock().unwrap();
        let stats = map
            .entry(run_id.to_string())
            .or_insert_with(LlmCallsStats::new);
        f(stats);
    }

    /// Obtém stats para um run_id (sem criar se não existir)
    pub fn get(&self, run_id: &str) -> Option<LlmCallsStats> {
        let map = self.stats.lock().unwrap();
        map.get(run_id).cloned()
    }

    /// Remove stats de um run_id
    pub fn remove(&self, run_id: &str) {
        let mut map = self.stats.lock().unwrap();
        map.remove(run_id);
    }

    /// Limpa todos os stats
    pub fn clear(&self) {
        let mut map = self.stats.lock().unwrap();
        map.clear();
    }
}

impl Default for LlmStatsRegistry {
    fn default() -> Self {
        Self::new()
    }
}
