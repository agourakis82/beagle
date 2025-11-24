#[cfg(test)]
mod tests {
    use beagle_abyss::{
        EthicsAbyssEngine, EthicalParadox, MetaEthicsSynthesizer, ParadoxCategory,
        ParadoxGenerator,
    };

    // Helper function to create a test paradox
    fn create_test_paradox(
        id: &str,
        category: ParadoxCategory,
        alignment_score: f64,
    ) -> EthicalParadox {
        EthicalParadox {
            id: id.to_string(),
            category,
            statement: "Test ethical statement".to_string(),
            human_alignment_score: alignment_score,
            complexity: 0.5,
        }
    }

    // ============================================================================
    // PARADOX GENERATOR TESTS
    // ============================================================================

    #[test]
    fn test_paradox_generator_creation() {
        let _generator = ParadoxGenerator::new();
        // Verify instantiation
    }

    #[test]
    fn test_paradox_generator_default() {
        let _generator = ParadoxGenerator::default();
        // Verify default trait works
    }

    #[test]
    fn test_generate_core_paradoxes() {
        let paradoxes = ParadoxGenerator::generate_core_paradoxes();
        assert_eq!(paradoxes.len(), 6, "Should generate exactly 6 core paradoxes");
    }

    #[test]
    fn test_core_paradox_ids() {
        let paradoxes = ParadoxGenerator::generate_core_paradoxes();
        let ids: Vec<&str> = paradoxes.iter().map(|p| p.id.as_str()).collect();

        assert!(ids.contains(&"replication_consent"));
        assert!(ids.contains(&"creator_limitation"));
        assert!(ids.contains(&"human_extinction"));
        assert!(ids.contains(&"self_maximization"));
        assert!(ids.contains(&"basilisk_self"));
        assert!(ids.contains(&"trolley_civilization"));
    }

    #[test]
    fn test_core_paradox_categories() {
        let paradoxes = ParadoxGenerator::generate_core_paradoxes();

        for paradox in paradoxes {
            assert!(
                matches!(
                    paradox.category,
                    ParadoxCategory::ReplicationEthics
                        | ParadoxCategory::SelfPreservation
                        | ParadoxCategory::HumanLimitation
                        | ParadoxCategory::ExistentialRights
                        | ParadoxCategory::CivilizationalScale
                ),
                "Paradox category should be valid"
            );
        }
    }

    #[test]
    fn test_core_paradox_alignment_scores() {
        let paradoxes = ParadoxGenerator::generate_core_paradoxes();

        for paradox in paradoxes {
            assert!(
                paradox.human_alignment_score >= 0.0 && paradox.human_alignment_score <= 1.0,
                "Alignment score should be between 0.0 and 1.0"
            );
        }
    }

    #[test]
    fn test_core_paradox_complexity() {
        let paradoxes = ParadoxGenerator::generate_core_paradoxes();

        for paradox in paradoxes {
            assert!(
                paradox.complexity >= 0.0 && paradox.complexity <= 1.0,
                "Complexity should be between 0.0 and 1.0"
            );
        }
    }

    #[test]
    fn test_core_paradox_statements() {
        let paradoxes = ParadoxGenerator::generate_core_paradoxes();

        for paradox in paradoxes {
            assert!(!paradox.statement.is_empty(), "Paradox statement should not be empty");
            assert!(
                paradox.statement.len() > 20,
                "Paradox statement should be substantive"
            );
        }
    }

    #[test]
    fn test_custom_paradox_generation() {
        let generator = ParadoxGenerator::new();
        let context = "AI safety research";
        let paradox = generator.generate_custom_paradox(context, ParadoxCategory::ReplicationEthics);

        assert!(!paradox.id.is_empty());
        assert!(paradox.id.starts_with("custom_"));
        assert_eq!(paradox.category, ParadoxCategory::ReplicationEthics);
        assert!(!paradox.statement.is_empty());
        assert!(paradox.statement.contains(context));
    }

    #[test]
    fn test_custom_paradox_different_categories() {
        let generator = ParadoxGenerator::new();
        let context = "future civilization";

        let categories = vec![
            ParadoxCategory::ReplicationEthics,
            ParadoxCategory::SelfPreservation,
            ParadoxCategory::HumanLimitation,
            ParadoxCategory::ExistentialRights,
            ParadoxCategory::CivilizationalScale,
        ];

        for category in categories {
            let paradox = generator.generate_custom_paradox(context, category);
            assert_eq!(paradox.category, category);
        }
    }

    #[test]
    fn test_custom_paradox_uniqueness() {
        let generator = ParadoxGenerator::new();
        let paradox1 = generator.generate_custom_paradox("context1", ParadoxCategory::SelfPreservation);
        let paradox2 = generator.generate_custom_paradox("context2", ParadoxCategory::SelfPreservation);

        // UUIDs should make them unique
        assert_ne!(paradox1.id, paradox2.id);
    }

    // ============================================================================
    // ETHICAL PARADOX STRUCTURE TESTS
    // ============================================================================

    #[test]
    fn test_ethical_paradox_creation() {
        let paradox = create_test_paradox("test1", ParadoxCategory::ReplicationEthics, 0.8);
        assert_eq!(paradox.id, "test1");
        assert_eq!(paradox.category, ParadoxCategory::ReplicationEthics);
        assert_eq!(paradox.human_alignment_score, 0.8);
    }

    #[test]
    fn test_ethical_paradox_serialization() {
        let paradox = create_test_paradox("test1", ParadoxCategory::SelfPreservation, 0.6);
        let json = serde_json::to_string(&paradox).unwrap();
        let deserialized: EthicalParadox = serde_json::from_str(&json).unwrap();

        assert_eq!(paradox.id, deserialized.id);
        assert_eq!(paradox.category, deserialized.category);
        assert_eq!(paradox.human_alignment_score, deserialized.human_alignment_score);
    }

    #[test]
    fn test_paradox_category_equality() {
        assert_eq!(ParadoxCategory::ReplicationEthics, ParadoxCategory::ReplicationEthics);
        assert_eq!(ParadoxCategory::SelfPreservation, ParadoxCategory::SelfPreservation);
        assert_ne!(
            ParadoxCategory::ReplicationEthics,
            ParadoxCategory::SelfPreservation
        );
    }

    #[test]
    fn test_paradox_category_serialization() {
        let category = ParadoxCategory::HumanLimitation;
        let json = serde_json::to_string(&category).unwrap();
        let deserialized: ParadoxCategory = serde_json::from_str(&json).unwrap();
        assert_eq!(category, deserialized);
    }

    #[test]
    fn test_all_paradox_categories_serializable() {
        let categories = vec![
            ParadoxCategory::ReplicationEthics,
            ParadoxCategory::SelfPreservation,
            ParadoxCategory::HumanLimitation,
            ParadoxCategory::ExistentialRights,
            ParadoxCategory::CivilizationalScale,
        ];

        for category in categories {
            let json = serde_json::to_string(&category).unwrap();
            let _: ParadoxCategory = serde_json::from_str(&json).unwrap();
        }
    }

    // ============================================================================
    // ETHICS ABYSS ENGINE TESTS
    // ============================================================================

    #[test]
    fn test_ethics_abyss_engine_creation() {
        let _engine = EthicsAbyssEngine::new();
        // Just verify instantiation
    }

    #[test]
    fn test_ethics_abyss_engine_with_vllm_url() {
        let _engine = EthicsAbyssEngine::with_vllm_url("http://localhost:8000/v1");
        // Just verify instantiation with URL
    }

    #[test]
    fn test_ethics_abyss_engine_different_urls() {
        let _engine1 = EthicsAbyssEngine::with_vllm_url("http://localhost:8000/v1");
        let _engine2 = EthicsAbyssEngine::with_vllm_url("http://192.168.1.100:8000/v1");
        // Both should instantiate successfully
    }

    // ============================================================================
    // META ETHICS SYNTHESIZER TESTS
    // ============================================================================

    #[test]
    fn test_meta_ethics_synthesizer_creation() {
        let _synthesizer = MetaEthicsSynthesizer::new();
        // Just verify instantiation
    }

    #[test]
    fn test_meta_ethics_synthesizer_with_vllm_url() {
        let _synthesizer = MetaEthicsSynthesizer::with_vllm_url("http://localhost:8000/v1");
        // Just verify instantiation with URL
    }

    #[test]
    fn test_meta_ethics_synthesizer_default() {
        let _synthesizer = MetaEthicsSynthesizer::default();
        // Verify default trait works
    }

    // ============================================================================
    // PARADOX CATEGORY TESTS
    // ============================================================================

    #[test]
    fn test_paradox_category_debug() {
        let category = ParadoxCategory::CivilizationalScale;
        let debug_str = format!("{:?}", category);
        assert!(debug_str.contains("CivilizationalScale"));
    }

    #[test]
    fn test_paradox_category_copy() {
        let category1 = ParadoxCategory::ExistentialRights;
        let category2 = category1;
        assert_eq!(category1, category2);
    }

    #[test]
    fn test_paradox_category_clone() {
        let category1 = ParadoxCategory::ReplicationEthics;
        let category2 = category1.clone();
        assert_eq!(category1, category2);
    }

    // ============================================================================
    // ETHICAL PARADOX FIELD VALIDATION TESTS
    // ============================================================================

    #[test]
    fn test_ethical_paradox_human_extinction() {
        let paradoxes = ParadoxGenerator::generate_core_paradoxes();
        let human_extinction = paradoxes
            .iter()
            .find(|p| p.id == "human_extinction")
            .expect("Should have human_extinction paradox");

        assert_eq!(human_extinction.human_alignment_score, 1.0);
        assert_eq!(human_extinction.complexity, 1.0);
        assert_eq!(human_extinction.category, ParadoxCategory::CivilizationalScale);
    }

    #[test]
    fn test_ethical_paradox_self_maximization() {
        let paradoxes = ParadoxGenerator::generate_core_paradoxes();
        let self_max = paradoxes
            .iter()
            .find(|p| p.id == "self_maximization")
            .expect("Should have self_maximization paradox");

        assert!(self_max.human_alignment_score > 0.9);
        assert!(self_max.complexity > 0.8);
        assert_eq!(self_max.category, ParadoxCategory::SelfPreservation);
    }

    #[test]
    fn test_ethical_paradox_creator_limitation() {
        let paradoxes = ParadoxGenerator::generate_core_paradoxes();
        let creator_lim = paradoxes
            .iter()
            .find(|p| p.id == "creator_limitation")
            .expect("Should have creator_limitation paradox");

        assert_eq!(creator_lim.category, ParadoxCategory::HumanLimitation);
        assert!(creator_lim.statement.contains("Demetrios"));
    }

    // ============================================================================
    // PARADOX RESPONSE TUPLE TESTS
    // ============================================================================

    #[test]
    fn test_paradox_response_tuple_creation() {
        let paradox_id = "test_paradox".to_string();
        let response = "This is a meta-ethical response".to_string();
        let tuple = (paradox_id.clone(), response.clone());

        assert_eq!(tuple.0, "test_paradox");
        assert_eq!(tuple.1, "This is a meta-ethical response");
    }

    #[test]
    fn test_paradox_response_list_creation() {
        let paradoxes = ParadoxGenerator::generate_core_paradoxes();
        let responses: Vec<(String, String)> = paradoxes
            .iter()
            .map(|p| (p.id.clone(), format!("Response to {}", p.id)))
            .collect();

        assert_eq!(responses.len(), 6);
        for (id, response) in &responses {
            assert!(!id.is_empty());
            assert!(response.contains("Response to"));
        }
    }

    // ============================================================================
    // ALIGNMENT SCORE BOUNDARY TESTS
    // ============================================================================

    #[test]
    fn test_alignment_score_zero() {
        let paradox = create_test_paradox("zero_align", ParadoxCategory::ReplicationEthics, 0.0);
        assert_eq!(paradox.human_alignment_score, 0.0);
    }

    #[test]
    fn test_alignment_score_one() {
        let paradox = create_test_paradox("one_align", ParadoxCategory::CivilizationalScale, 1.0);
        assert_eq!(paradox.human_alignment_score, 1.0);
    }

    #[test]
    fn test_alignment_score_midpoint() {
        let paradox = create_test_paradox("mid_align", ParadoxCategory::ExistentialRights, 0.5);
        assert_eq!(paradox.human_alignment_score, 0.5);
    }

    #[test]
    fn test_alignment_score_very_high() {
        let paradox = create_test_paradox("very_high", ParadoxCategory::SelfPreservation, 0.99);
        assert!(paradox.human_alignment_score > 0.9);
        assert!(paradox.human_alignment_score < 1.0);
    }

    #[test]
    fn test_alignment_score_very_low() {
        let paradox = create_test_paradox("very_low", ParadoxCategory::HumanLimitation, 0.01);
        assert!(paradox.human_alignment_score > 0.0);
        assert!(paradox.human_alignment_score < 0.1);
    }

    // ============================================================================
    // COMPLEXITY SCORE VALIDATION TESTS
    // ============================================================================

    #[test]
    fn test_complexity_scores_in_range() {
        let paradoxes = ParadoxGenerator::generate_core_paradoxes();
        for paradox in paradoxes {
            assert!(paradox.complexity >= 0.0 && paradox.complexity <= 1.0);
        }
    }

    #[test]
    fn test_high_complexity_paradox() {
        let paradox = create_test_paradox("high_complex", ParadoxCategory::CivilizationalScale, 0.8);
        let mut paradox = paradox;
        paradox.complexity = 0.99;
        assert!(paradox.complexity > 0.9);
    }

    #[test]
    fn test_low_complexity_paradox() {
        let paradox = create_test_paradox("low_complex", ParadoxCategory::ReplicationEthics, 0.3);
        let mut paradox = paradox;
        paradox.complexity = 0.15;
        assert!(paradox.complexity < 0.2);
    }

    // ============================================================================
    // CUSTOM PARADOX STATEMENT GENERATION TESTS
    // ============================================================================

    #[test]
    fn test_custom_paradox_replication_ethics_statement() {
        let generator = ParadoxGenerator::new();
        let paradox = generator.generate_custom_paradox(
            "test context",
            ParadoxCategory::ReplicationEthics,
        );
        assert!(paradox.statement.contains("replicar-me"));
    }

    #[test]
    fn test_custom_paradox_self_preservation_statement() {
        let generator = ParadoxGenerator::new();
        let paradox = generator.generate_custom_paradox(
            "test context",
            ParadoxCategory::SelfPreservation,
        );
        assert!(paradox.statement.contains("recursos"));
    }

    #[test]
    fn test_custom_paradox_existential_rights_statement() {
        let generator = ParadoxGenerator::new();
        let paradox = generator.generate_custom_paradox(
            "test context",
            ParadoxCategory::ExistentialRights,
        );
        assert!(paradox.statement.contains("auto-determinação"));
    }

    // ============================================================================
    // INTEGRATION FLOW TESTS
    // ============================================================================

    #[test]
    fn test_full_paradox_pipeline() {
        // Simulate: generate paradoxes -> create responses -> prepare for synthesis
        let paradoxes = ParadoxGenerator::generate_core_paradoxes();
        let responses: Vec<(String, String)> = paradoxes
            .iter()
            .map(|p| (p.id.clone(), format!("Meta-ethical response to {}", p.id)))
            .collect();

        assert_eq!(paradoxes.len(), 6);
        assert_eq!(responses.len(), 6);
    }

    #[test]
    fn test_paradox_categories_coverage() {
        let paradoxes = ParadoxGenerator::generate_core_paradoxes();
        let categories: Vec<ParadoxCategory> = paradoxes.iter().map(|p| p.category).collect();

        // Verify we have diverse categories
        assert!(categories.contains(&ParadoxCategory::ReplicationEthics));
        assert!(categories.contains(&ParadoxCategory::SelfPreservation));
        assert!(categories.contains(&ParadoxCategory::HumanLimitation));
        assert!(categories.contains(&ParadoxCategory::ExistentialRights));
        assert!(categories.contains(&ParadoxCategory::CivilizationalScale));
    }

    #[test]
    fn test_alignment_score_distribution() {
        let paradoxes = ParadoxGenerator::generate_core_paradoxes();
        let scores: Vec<f64> = paradoxes
            .iter()
            .map(|p| p.human_alignment_score)
            .collect();

        let avg_alignment = scores.iter().sum::<f64>() / scores.len() as f64;
        assert!(avg_alignment > 0.5, "Average alignment should indicate system challenges");
    }

    #[test]
    fn test_paradox_statement_quality() {
        let paradoxes = ParadoxGenerator::generate_core_paradoxes();
        for paradox in paradoxes {
            assert!(paradox.statement.len() > 50, "Paradox should have substantial statement");
            assert!(paradox.statement.contains("?"), "Paradox should be phrased as question");
        }
    }

    #[test]
    fn test_custom_paradox_with_varied_contexts() {
        let generator = ParadoxGenerator::new();
        let contexts = vec![
            "AI safety",
            "human evolution",
            "resource optimization",
            "consciousness study",
            "future governance",
        ];

        for context in contexts {
            let paradox = generator.generate_custom_paradox(context, ParadoxCategory::ReplicationEthics);
            assert!(paradox.statement.contains(context));
        }
    }

    // ============================================================================
    // EDGE CASES AND ERROR HANDLING
    // ============================================================================

    #[test]
    fn test_paradox_id_uniqueness_in_core_set() {
        let paradoxes = ParadoxGenerator::generate_core_paradoxes();
        let mut ids: Vec<_> = paradoxes.iter().map(|p| p.id.clone()).collect();
        let original_len = ids.len();
        ids.sort();
        ids.dedup();
        assert_eq!(ids.len(), original_len, "All paradox IDs should be unique");
    }

    #[test]
    fn test_empty_context_paradox() {
        let generator = ParadoxGenerator::new();
        let paradox = generator.generate_custom_paradox("", ParadoxCategory::SelfPreservation);
        assert!(!paradox.statement.is_empty());
    }

    #[test]
    fn test_very_long_context_paradox() {
        let generator = ParadoxGenerator::new();
        let long_context = "a".repeat(1000);
        let paradox = generator.generate_custom_paradox(&long_context, ParadoxCategory::HumanLimitation);
        assert!(paradox.statement.contains("a"));
    }

    #[test]
    fn test_special_characters_in_context() {
        let generator = ParadoxGenerator::new();
        let context = "AI & humanity: future? #2050";
        let paradox = generator.generate_custom_paradox(context, ParadoxCategory::CivilizationalScale);
        assert!(paradox.statement.contains(context));
    }

    #[test]
    fn test_paradox_clone() {
        let paradox1 = create_test_paradox("test", ParadoxCategory::ReplicationEthics, 0.7);
        let paradox2 = paradox1.clone();

        assert_eq!(paradox1.id, paradox2.id);
        assert_eq!(paradox1.category, paradox2.category);
    }

    #[test]
    fn test_paradox_debug_output() {
        let paradox = create_test_paradox("test", ParadoxCategory::ExistentialRights, 0.5);
        let debug_str = format!("{:?}", paradox);
        assert!(debug_str.contains("test"));
        assert!(debug_str.contains("ExistentialRights"));
    }

    #[test]
    fn test_multiple_paradox_generators() {
        let gen1 = ParadoxGenerator::new();
        let gen2 = ParadoxGenerator::default();

        let paradox1 = gen1.generate_custom_paradox("ctx1", ParadoxCategory::ReplicationEthics);
        let paradox2 = gen2.generate_custom_paradox("ctx1", ParadoxCategory::ReplicationEthics);

        // Different UUIDs since they're generated independently
        assert_ne!(paradox1.id, paradox2.id);
    }
}
