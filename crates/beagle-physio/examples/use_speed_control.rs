//! Exemplo de uso do speed_control no loop adversarial
//!
//! Roda com: cargo run --example use_speed_control --package beagle-physio

use beagle_physio::speed_control;
use std::time::Duration;
use tokio::time::sleep;

#[tokio::main]
async fn main() {
    println!("═══════════════════════════════════════════════════════════════");
    println!("  BEAGLE Speed Control - Exemplo de Uso");
    println!("═══════════════════════════════════════════════════════════════");
    println!();

    // Loop simulado que usa o multiplicador de velocidade
    for i in 1..=10 {
        let base_delay = 1000; // 1 segundo base

        // Obtém delay ajustado baseado no HRV
        let adjusted_delay = speed_control::get_adjusted_delay(base_delay);
        let multiplier = speed_control::get_global_speed_multiplier();

        println!(
            "Iteração {}: delay={}ms, multiplicador={:.1}x",
            i, adjusted_delay, multiplier
        );

        // Simula trabalho
        sleep(Duration::from_millis(adjusted_delay)).await;

        // Simula mudança de estado (FLOW → STRESS → NORMAL)
        match i {
            3 => {
                speed_control::set_global_speed_multiplier(1.5);
                println!("  → Estado FLOW: acelerando loop");
            }
            6 => {
                speed_control::set_global_speed_multiplier(0.7);
                println!("  → Estado STRESS: desacelerando loop");
            }
            9 => {
                speed_control::set_global_speed_multiplier(1.0);
                println!("  → Estado NORMAL: velocidade normal");
            }
            _ => {}
        }
    }

    println!();
    println!("✅ Exemplo concluído");
}
