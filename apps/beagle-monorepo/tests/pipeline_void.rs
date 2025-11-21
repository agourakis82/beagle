//! Testes de integração Void no pipeline

use beagle_monorepo::pipeline_void::{DeadlockState, handle_deadlock};

#[tokio::test]
async fn test_deadlock_detection() {
    let mut state = DeadlockState::new("test_run".to_string());
    
    // Adiciona outputs similares
    assert!(!state.add_output("Output 1: Test content"));
    assert!(!state.add_output("Output 2: Test content")); // Similar
    assert!(!state.add_output("Output 3: Test content")); // Similar
    assert!(!state.add_output("Output 4: Test content")); // Similar
    assert!(!state.add_output("Output 5: Test content")); // Similar - deve detectar deadlock
    
    // Com BEAGLE_VOID_STRICT, threshold é 3
    std::env::set_var("BEAGLE_VOID_STRICT", "true");
    let mut state_strict = DeadlockState::new("test_run_strict".to_string());
    assert!(!state_strict.add_output("Same output"));
    assert!(!state_strict.add_output("Same output"));
    assert!(state_strict.add_output("Same output")); // Deve detectar deadlock no 3º
}

#[tokio::test]
#[ignore] // Requer BEAGLE_VOID_ENABLE=true
async fn test_void_break_loop() -> anyhow::Result<()> {
    std::env::set_var("BEAGLE_VOID_ENABLE", "true");
    
    let result = handle_deadlock(
        "test_run",
        "Test deadlock",
        "Test focus",
    ).await?;
    
    assert!(result.contains("VOID BREAK APPLIED"));
    
    Ok(())
}

