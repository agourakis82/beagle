//! Controle de velocidade global do loop baseado em HRV

use std::sync::{Mutex, OnceLock};

/// Multiplicador global de velocidade do loop (1.0 = normal)
static GLOBAL_SPEED_MULTIPLIER: OnceLock<Mutex<f64>> = OnceLock::new();

fn get_multiplier_mutex() -> &'static Mutex<f64> {
    GLOBAL_SPEED_MULTIPLIER.get_or_init(|| Mutex::new(1.0))
}

/// Retorna o multiplicador de velocidade atual
pub fn get_global_speed_multiplier() -> f64 {
    *get_multiplier_mutex().lock().unwrap()
}

/// Define o multiplicador de velocidade
pub fn set_global_speed_multiplier(multiplier: f64) {
    *get_multiplier_mutex().lock().unwrap() = multiplier;
}

/// Calcula delay ajustado baseado no multiplicador
pub fn get_adjusted_delay(base_delay_ms: u64) -> u64 {
    let multiplier = get_global_speed_multiplier();
    (base_delay_ms as f64 / multiplier) as u64
}
