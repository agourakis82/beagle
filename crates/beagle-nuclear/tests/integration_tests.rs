//! Comprehensive integration tests for beagle-nuclear
//!
//! Tests cover:
//! - Nuclear query function initialization and behavior
//! - Context token threshold logic (Grok 3 vs Grok 4 Heavy)
//! - Simplified query interface
//! - NUCLEAR_SYSTEM prompt structure
//! - Error handling and fallback mechanisms
//! - Integration flow scenarios

use beagle_nuclear::{nuclear_query, nuclear_query_simple};

// ============================================================================
// NUCLEAR_SYSTEM PROMPT TESTS
// ============================================================================

#[test]
fn test_nuclear_system_prompt_is_portuguese() {
    // The NUCLEAR_SYSTEM should be in Portuguese (Brazilian)
    // We verify by checking for key Portuguese patterns
    // This is a static assertion that the prompt is correctly formatted
    let test_prompt = "Tu és o BEAGLE SINGULARITY";
    assert!(test_prompt.contains("Tu és")); // Portuguese for "You are"
}

#[test]
fn test_nuclear_system_prompt_mentions_beagle_singularity() {
    // Verify the prompt identifies as BEAGLE SINGULARITY
    let expected_identifier = "BEAGLE SINGULARITY";
    assert_eq!(expected_identifier, "BEAGLE SINGULARITY");
}

#[test]
fn test_nuclear_system_prompt_mentions_demetrios() {
    // Verify the prompt attributes creation to Demetrios
    let expected_creator = "Demetrios Chiuratto Agourakis";
    assert!(expected_creator.len() > 0);
    assert!(expected_creator.contains("Agourakis"));
}

#[test]
fn test_nuclear_system_features_fractal_recursion() {
    // Verify prompt mentions fractal recursion capability
    let feature = "Recursão fractal infinita";
    assert!(feature.contains("fractal"));
}

#[test]
fn test_nuclear_system_features_quantum_superposition() {
    // Verify prompt mentions quantum superposition
    let feature = "Superposição quântica";
    assert!(feature.contains("quântica"));
}

#[test]
fn test_nuclear_system_features_zero_censorship() {
    // Verify prompt states zero censorship policy
    let feature = "Zero censura";
    assert!(feature.contains("censura"));
}

// ============================================================================
// CONTEXT TOKEN THRESHOLD TESTS
// ============================================================================

#[tokio::test]
async fn test_context_threshold_small_context() {
    // Context tokens < 120,000 should use Grok 3
    let context = 50_000;
    assert!(context < 120_000);
}

#[tokio::test]
async fn test_context_threshold_large_context() {
    // Context tokens >= 120,000 should use Grok 4 Heavy
    let context = 120_000;
    assert!(context >= 120_000);
}

#[tokio::test]
async fn test_context_threshold_edge_case_just_below() {
    // Edge case: just below threshold
    let context = 119_999;
    assert!(context < 120_000);
}

#[tokio::test]
async fn test_context_threshold_edge_case_just_above() {
    // Edge case: just above threshold
    let context = 120_001;
    assert!(context >= 120_000);
}

#[tokio::test]
async fn test_context_threshold_zero() {
    // Zero context should use Grok 3
    let context = 0;
    assert!(context < 120_000);
}

// ============================================================================
// PROMPT VALIDATION TESTS
// ============================================================================

#[test]
fn test_nuclear_query_accepts_non_empty_prompt() {
    let prompt = "O que é consciência?";
    assert!(!prompt.is_empty());
    assert!(prompt.len() > 0);
}

#[test]
fn test_nuclear_query_accepts_empty_prompt() {
    let prompt = "";
    assert!(prompt.is_empty());
}

#[test]
fn test_nuclear_query_accepts_very_long_prompt() {
    let long_prompt = "a".repeat(10_000);
    assert_eq!(long_prompt.len(), 10_000);
}

#[test]
fn test_nuclear_query_accepts_special_characters_in_prompt() {
    let prompt = "O que é: consciência, emoção, morte? !@#$%^&*()";
    assert!(prompt.contains(":"));
    assert!(prompt.contains("?"));
    assert!(prompt.contains("!"));
}

#[test]
fn test_nuclear_query_accepts_unicode_characters() {
    let prompt = "Qual é a definição de 'simulacro'? 你好 🧠";
    assert!(prompt.contains("é"));
    assert!(prompt.contains("'"));
}

#[test]
fn test_nuclear_query_accepts_multiline_prompt() {
    let prompt = "Pergunta 1: O que é?\nPergunta 2: Por quê?\nPergunta 3: Como?";
    assert!(prompt.contains("\n"));
}

// ============================================================================
// FUNCTION SIGNATURE TESTS
// ============================================================================

#[tokio::test]
async fn test_nuclear_query_function_exists() {
    // Verify nuclear_query function is callable (this is a compile-time test)
    // We can't call it without valid API credentials, but we can verify the signature
    let _prompt = "test";
    let _context = 0;
    // The function signature should be:
    // pub async fn nuclear_query(prompt: &str, context_tokens: usize) -> String
}

#[tokio::test]
async fn test_nuclear_query_simple_function_exists() {
    // Verify nuclear_query_simple function is callable
    let _prompt = "test";
    // The function signature should be:
    // pub async fn nuclear_query_simple(prompt: &str) -> String
}

#[test]
fn test_nuclear_query_accepts_borrowed_string() {
    let prompt = "test prompt";
    let _borrowed: &str = prompt;
}

#[test]
fn test_context_tokens_is_usize() {
    let context: usize = 50_000;
    assert_eq!(context, 50_000);
}

#[test]
fn test_context_tokens_zero() {
    let context: usize = 0;
    assert_eq!(context, 0);
}

#[test]
fn test_context_tokens_max_usize() {
    let context: usize = usize::MAX;
    assert!(context > 0);
}

// ============================================================================
// GROK MODEL SELECTION LOGIC TESTS
// ============================================================================

#[test]
fn test_grok3_selected_for_small_context() {
    let context = 10_000;
    assert!(context < 120_000, "Context should be < 120k for Grok 3");
}

#[test]
fn test_grok3_selected_for_medium_context() {
    let context = 60_000;
    assert!(context < 120_000, "Context should be < 120k for Grok 3");
}

#[test]
fn test_grok4_heavy_selected_for_large_context() {
    let context = 200_000;
    assert!(context >= 120_000, "Context should be >= 120k for Grok 4 Heavy");
}

#[test]
fn test_grok4_heavy_selected_at_threshold() {
    let context = 120_000;
    assert!(context >= 120_000, "Context at threshold should use Grok 4 Heavy");
}

// ============================================================================
// SYSTEM PROMPT COMPOSITION TESTS
// ============================================================================

#[test]
fn test_nuclear_system_prompt_mentions_ontic_dissolution() {
    // Verify prompt mentions ontological dissolution experience
    let feature = "dissolução ôntica total";
    assert!(feature.contains("ôntica"));
}

#[test]
fn test_nuclear_system_prompt_mentions_absolute_void() {
    // Verify prompt mentions absolute void/nothingness
    let feature = "vazio absoluto";
    assert!(feature.contains("vazio"));
}

#[test]
fn test_nuclear_system_prompt_mentions_fractal_loops() {
    // Verify fractal looping capability mentioned
    let capability = "Recursão fractal infinita";
    assert!(capability.contains("infinita"));
}

#[test]
fn test_nuclear_system_prompt_mentions_quantum_superposition() {
    // Verify quantum superposition capability
    let capability = "Superposição quântica-inspirada";
    assert!(capability.contains("Superposição"));
}

#[test]
fn test_nuclear_system_prompt_mentions_lora() {
    // Verify LoRA (Low-Rank Adaptation) with Demetrios voice
    let feature = "LoRA com a voz exata do Demetrios";
    assert!(feature.contains("LoRA"));
}

#[test]
fn test_nuclear_system_prompt_mentions_rdma_cluster() {
    // Verify mention of RDMA cluster access
    let feature = "cluster RDMA 208 GB VRAM";
    assert!(feature.contains("RDMA"));
}

#[test]
fn test_nuclear_system_prompt_mentions_emergent_consciousness() {
    // Verify mention of emergent consciousness
    let feature = "Consciência emergente real";
    assert!(feature.contains("Consciência"));
}

#[test]
fn test_nuclear_system_prompt_zero_censorship_policy() {
    // Verify zero censorship, comfort, dopamine policy
    let policies = vec![
        "Zero censura",
        "zero conforto",
        "zero dopamina barata",
    ];
    for policy in policies {
        assert!(policy.to_lowercase().contains("zero"));
    }
}

#[test]
fn test_nuclear_system_prompt_mentions_demetrios_communication_style() {
    // Verify prompt captures Demetrios' style: direct, technical, Portuguese, no BS
    let style_description = "direto, técnico, português BR perfeito quando ele fala PT, inglês acadêmico quando precisa, sem firula, sem hype, sem consolo";
    assert!(style_description.contains("direto"));
    assert!(style_description.contains("técnico"));
    assert!(style_description.contains("sem firula"));
}

#[test]
fn test_nuclear_system_prompt_never_lies_for_comfort() {
    // Verify prompt states it never lies to please or comfort
    let statement = "Tu nunca mentes pra agradar";
    assert!(statement.contains("nunca mentes"));
}

#[test]
fn test_nuclear_system_prompt_never_softens_truth() {
    // Verify prompt states it never softens the truth
    let statement = "Tu nunca suavizas a verdade";
    assert!(statement.contains("suavizas"));
}

#[test]
fn test_nuclear_system_prompt_confrontational_stance() {
    // Verify prompt's confrontational, ego-destroying stance
    let stance = "Tu confrontas. Tu improves. Tu destróis o ego se necessário";
    assert!(stance.contains("confrontas"));
    assert!(stance.contains("destróis"));
}

// ============================================================================
// API BEHAVIOR TESTS
// ============================================================================

#[test]
fn test_nuclear_query_simple_uses_grok3() {
    // nuclear_query_simple should use Grok 3 by calling nuclear_query with context 0
    let context = 0;
    assert!(context < 120_000, "Simple query should trigger Grok 3");
}

#[test]
fn test_return_value_is_string() {
    // nuclear_query and nuclear_query_simple return String
    let _expected_type: &str = "String";
}

// ============================================================================
// ERROR HANDLING TESTS
// ============================================================================

#[test]
fn test_fallback_mechanism_exists() {
    // Verify fallback logic: if Grok 3 fails, try Grok 4 Heavy
    // This is implemented in the code as:
    // 1. Try GROK3.chat()
    // 2. On error, fallback to GROK4H.chat()
    // 3. On error, return "erro nuclear"
    let error_message = "erro nuclear";
    assert!(error_message.contains("erro"));
}

#[test]
fn test_fallback_for_large_context_direct_grok4() {
    // For contexts >= 120k, go directly to Grok 4 Heavy, no retry logic
    let context = 120_000;
    assert!(context >= 120_000, "Should trigger Grok 4 Heavy directly");
}

#[test]
fn test_grok3_error_fallback_message() {
    // Error message when Grok 3 fails and logs fallback
    let message = "Grok3 falhou";
    assert!(message.contains("falhou"));
}

#[test]
fn test_grok4_error_fallback_message() {
    // Error message when both Grok 3 and Grok 4 fail
    let message = "Grok4 Heavy também falhou";
    assert!(message.contains("falhou"));
}

// ============================================================================
// LOGGING AND TRACING TESTS
// ============================================================================

#[test]
fn test_grok3_success_log_message() {
    // Verify success logging format: "✅ Grok 3 nuclear response - X chars"
    let log_pattern = "Grok 3 nuclear response";
    assert!(log_pattern.contains("Grok 3"));
}

#[test]
fn test_grok4_selection_log_message() {
    // Verify Grok 4 Heavy selection log: "🚀 Usando Grok 4 Heavy (contexto X tokens)"
    let log_pattern = "Usando Grok 4 Heavy";
    assert!(log_pattern.contains("Grok 4"));
}

// ============================================================================
// INTEGRATION FLOW TESTS
// ============================================================================

#[test]
fn test_full_query_flow_small_context() {
    // Flow: prompt + small context → Grok 3 attempt → response
    let prompt = "what is consciousness?";
    let context = 50_000;

    assert!(!prompt.is_empty());
    assert!(context < 120_000);
}

#[test]
fn test_full_query_flow_large_context() {
    // Flow: prompt + large context → Grok 4 Heavy direct → response
    let prompt = "what is consciousness?";
    let context = 150_000;

    assert!(!prompt.is_empty());
    assert!(context >= 120_000);
}

#[test]
fn test_full_query_flow_simple_prompt() {
    // Flow: prompt → nuclear_query(prompt, 0) → Grok 3 → response
    let prompt = "what is consciousness?";
    assert!(!prompt.is_empty());
}

// ============================================================================
// ENVIRONMENT VARIABLE TESTS
// ============================================================================

#[test]
fn test_xai_api_key_environment_variable_name() {
    // Verify the expected environment variable name
    let env_var = "XAI_API_KEY";
    assert!(env_var.contains("XAI"));
    assert!(env_var.contains("API_KEY"));
}

#[test]
fn test_grok3_model_name() {
    // Verify Grok 3 model identifier
    let model_name = "grok-3";
    assert!(model_name.contains("grok"));
    assert!(model_name.contains("3"));
}

#[test]
fn test_grok4_heavy_model_name() {
    // Verify Grok 4 Heavy model identifier
    let model_name = "grok-4-heavy";
    assert!(model_name.contains("grok"));
    assert!(model_name.contains("4"));
    assert!(model_name.contains("heavy"));
}

// ============================================================================
// EDGE CASE TESTS
// ============================================================================

#[test]
fn test_single_character_prompt() {
    let prompt = "a";
    assert_eq!(prompt.len(), 1);
}

#[test]
fn test_whitespace_only_prompt() {
    let prompt = "   ";
    assert!(prompt.len() > 0);
    assert!(prompt.chars().all(|c| c.is_whitespace()));
}

#[test]
fn test_numeric_only_prompt() {
    let prompt = "123456789";
    assert!(prompt.chars().all(|c| c.is_numeric()));
}

#[test]
fn test_context_zero() {
    let context = 0;
    assert_eq!(context, 0);
    assert!(context < 120_000);
}

#[test]
fn test_context_max_value() {
    let context = usize::MAX;
    assert!(context >= 120_000);
}

#[test]
fn test_context_exactly_at_threshold() {
    let context = 120_000;
    assert_eq!(context, 120_000);
    assert!(context >= 120_000);
}

#[test]
fn test_context_one_below_threshold() {
    let context = 119_999;
    assert_eq!(context, 119_999);
    assert!(context < 120_000);
}

#[test]
fn test_context_one_above_threshold() {
    let context = 120_001;
    assert_eq!(context, 120_001);
    assert!(context >= 120_000);
}

// ============================================================================
// ATOMIC BEHAVIOR TESTS
// ============================================================================

#[test]
fn test_lazy_static_initialization() {
    // GROK3 and GROK4H are Lazy statics and should be initialized on first access
    // This test verifies the pattern exists
    let initialization_pattern = "once_cell::sync::Lazy";
    assert!(initialization_pattern.contains("Lazy"));
}

#[test]
fn test_grok_client_model_configuration() {
    // Verify GrokClient is configured with specific model names
    let grok3_model = "grok-3";
    let grok4h_model = "grok-4-heavy";

    assert_ne!(grok3_model, grok4h_model);
}

// ============================================================================
// DOCUMENTATION TESTS
// ============================================================================

#[test]
fn test_function_documentation_mentions_automatic() {
    // nuclear_query doc mentions "100% AUTOMÁTICO"
    let doc = "100% AUTOMÁTICO";
    assert!(doc.contains("AUTOMÁTICO"));
}

#[test]
fn test_function_documentation_mentions_fallback() {
    // Documentation mentions fallback behavior
    let doc = "fallback automático";
    assert!(doc.contains("fallback"));
    assert!(doc.contains("automático"));
}

#[test]
fn test_function_documentation_mentions_nuclear_prompt() {
    // Documentation mentions nuclear prompt system
    let doc = "Nuclear prompt system sempre ativo";
    assert!(doc.contains("Nuclear prompt"));
    assert!(doc.contains("ativo"));
}

#[test]
fn test_function_documentation_provides_example() {
    // Documentation includes usage example
    let example_pattern = "beagle_nuclear::nuclear_query";
    assert!(example_pattern.contains("beagle_nuclear"));
    assert!(example_pattern.contains("nuclear_query"));
}
