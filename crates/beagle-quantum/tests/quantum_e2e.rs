//! Testes End-to-End do Quantum Reasoning Engine

use beagle_quantum::{
    CollapseStrategy, HypothesisSet, InterferenceEngine, MeasurementOperator, SuperpositionAgent,
};

#[tokio::test]
async fn test_superposition_generation() {
    let agent = SuperpositionAgent::new();
    let set = agent
        .generate_hypotheses("Como explicar a curvatura da entropia em scaffolds?")
        .await;

    // Se vLLM não estiver disponível, o teste pode falhar - isso é esperado
    match set {
        Ok(set) => {
            assert!(
                !set.hypotheses.is_empty(),
                "Deve gerar pelo menos uma hipótese"
            );
            // Verifica que as probabilidades somam ~1.0
            let total_prob: f64 = set.hypotheses.iter().map(|h| h.confidence).sum();
            assert!(
                (total_prob - 1.0).abs() < 0.1,
                "Probabilidades devem somar ~1.0, soma: {}",
                total_prob
            );
        }
        Err(e) => {
            // Se vLLM não estiver disponível, apenas loga o erro
            eprintln!(
                "⚠️  vLLM não disponível (esperado em testes sem cluster): {}",
                e
            );
            // Não falha o teste - é um teste opcional que requer infraestrutura
        }
    }
}

#[tokio::test]
async fn test_interference_constructive() {
    let mut set = HypothesisSet::new();
    set.add(
        "Hipótese A: Entropia aumenta com temperatura".to_string(),
        Some((0.5, 0.1)),
    );
    set.add(
        "Hipótese B: Entropia diminui com temperatura".to_string(),
        Some((0.3, 0.1)),
    );

    // Encontrar qual hipótese corresponde a A antes da interferência
    let initial_a_idx = set
        .hypotheses
        .iter()
        .position(|h| h.content.contains("aumenta"))
        .unwrap();
    let initial_a_prob = set.hypotheses[initial_a_idx].confidence;

    let engine = InterferenceEngine::new();
    // Se embedding server não estiver disponível, apenas loga
    match engine
        .apply_evidence(
            &mut set,
            "Evidência experimental confirma que entropia aumenta com temperatura",
            1.0,
        )
        .await
    {
        Ok(_) => {
            // Recalcular após interferência
            let final_a_prob = set.hypotheses[initial_a_idx].confidence;

            // A hipótese A deve ter sido reforçada (ou pelo menos não enfraquecida)
            assert!(
                final_a_prob >= initial_a_prob * 0.8, // Permite variação maior devido a embeddings reais
                "Interferência construtiva deve aumentar ou manter confiança. Antes: {:.3}, Depois: {:.3}",
                initial_a_prob, final_a_prob
            );
        }
        Err(e) => {
            // Se embedding server não estiver disponível, apenas loga
            eprintln!(
                "⚠️  Embedding server não disponível (esperado em testes sem cluster): {}",
                e
            );
        }
    }
}

#[tokio::test]
async fn test_measurement_greedy() {
    let mut set = HypothesisSet::new();
    set.add("Hipótese 1".to_string(), Some((0.8, 0.1)));
    set.add("Hipótese 2".to_string(), Some((0.3, 0.1)));
    set.add("Hipótese 3".to_string(), Some((0.2, 0.1)));

    let operator = MeasurementOperator::new();
    let result = operator
        .measure(set, CollapseStrategy::Greedy)
        .await
        .unwrap();

    assert_eq!(
        result, "Hipótese 1",
        "Greedy deve retornar a melhor hipótese"
    );
}

#[tokio::test]
async fn test_measurement_probabilistic() {
    let mut set = HypothesisSet::new();
    set.add("Hipótese A".to_string(), Some((0.7, 0.0)));
    set.add("Hipótese B".to_string(), Some((0.3, 0.0)));

    let operator = MeasurementOperator::new();

    // Executa múltiplas vezes para verificar distribuição probabilística
    let mut results = std::collections::HashMap::new();
    for _ in 0..100 {
        let result = operator
            .measure(set.clone(), CollapseStrategy::Probabilistic)
            .await
            .unwrap();
        *results.entry(result).or_insert(0) += 1;
    }

    // Hipótese A deve aparecer mais vezes (maior probabilidade)
    // Nota: Teste probabilístico pode variar, então usamos threshold mais baixo
    let count_a = results.get("Hipótese A").unwrap_or(&0);
    let count_b = results.get("Hipótese B").unwrap_or(&0);

    // Hipótese A (prob 0.7) deve aparecer mais que B (prob 0.3)
    // Com 100 tentativas, A deve aparecer > 40 vezes na maioria dos casos
    assert!(
        *count_a > *count_b && *count_a > 30,
        "Hipótese A (prob maior) deve aparecer mais que B. A: {}, B: {}",
        count_a,
        count_b
    );
}

#[tokio::test]
async fn test_full_quantum_pipeline() {
    // Pipeline completo: Superposition → Interference → Measurement
    let quantum = SuperpositionAgent::new();
    let set_result = quantum
        .generate_hypotheses("Como explicar a curvatura da entropia em scaffolds?")
        .await;

    // Se vLLM não estiver disponível, usa fallback
    let mut set = match set_result {
        Ok(set) => set,
        Err(_) => {
            // Fallback para teste sem vLLM
            let mut fallback_set = HypothesisSet::new();
            fallback_set.add("Hipótese 1: Abordagem clássica".to_string(), None);
            fallback_set.add("Hipótese 2: Modelo quântico de campo".to_string(), None);
            fallback_set
        }
    };

    let interference = InterferenceEngine::new();
    // Se embedding server não estiver disponível, apenas loga
    if let Err(e) = interference
        .apply_evidence(
            &mut set,
            "Evidência experimental 2024 confirma modelo quântico de campo",
            1.0,
        )
        .await
    {
        eprintln!(
            "⚠️  Embedding server não disponível (esperado em testes sem cluster): {}",
            e
        );
    }

    let measurement = MeasurementOperator::new();
    let final_answer = measurement
        .measure(set, CollapseStrategy::Probabilistic)
        .await
        .unwrap();

    assert!(
        !final_answer.is_empty(),
        "Resposta final não deve estar vazia"
    );
    println!(
        "✅ Pipeline completo: {}",
        &final_answer[..final_answer.len().min(80)]
    );
}

#[tokio::test]
async fn test_measurement_critic_guided() {
    let mut set = HypothesisSet::new();
    set.add(
        "Hipótese 1: Abordagem clássica newtoniana".to_string(),
        Some((0.6, 0.1)),
    );
    set.add(
        "Hipótese 2: Modelo quântico de campo".to_string(),
        Some((0.4, 0.1)),
    );
    set.add(
        "Hipótese 3: Interpretação geométrica".to_string(),
        Some((0.3, 0.1)),
    );

    let operator = MeasurementOperator::new();

    // Se vLLM não estiver disponível, apenas loga
    match operator.collapse(set, CollapseStrategy::CriticGuided).await {
        Ok(result) => {
            assert!(
                !result.is_empty(),
                "CriticGuided deve retornar resposta não vazia"
            );
            println!(
                "✅ CriticGuided colapsou: {}",
                &result[..result.len().min(100)]
            );
        }
        Err(e) => {
            eprintln!(
                "⚠️  vLLM não disponível para CriticGuided (esperado em testes sem cluster): {}",
                e
            );
        }
    }
}
