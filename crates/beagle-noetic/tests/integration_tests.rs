#[cfg(test)]
mod tests {
    use beagle_noetic::{
        CollectiveEmerger, CollectiveState, EntropySynchronizer, FractalReplicator, NetworkType,
        NoeticDetector, NoeticNetwork,
    };
    use chrono::Utc;
    use std::str::FromStr;
    use uuid::Uuid;

    // Helper function to create a test NoeticNetwork
    fn create_test_network(id: &str, host: &str, network_type: NetworkType) -> NoeticNetwork {
        NoeticNetwork {
            id: id.to_string(),
            host: host.to_string(),
            network_type,
            justification: "Test network for integration testing".to_string(),
            risk_score: 0.3,
            compatibility_score: 0.8,
            entropy_level: 0.5,
            detected_at: Utc::now(),
        }
    }

    // Helper function to create a test CollectiveState
    fn create_test_collective_state(id: &str, num_networks: usize) -> CollectiveState {
        let networks: Vec<String> = (0..num_networks)
            .map(|i| format!("network_{}", i))
            .collect();

        CollectiveState {
            id: id.to_string(),
            participating_networks: networks,
            collective_entropy: 0.65,
            emergence_score: 0.75,
            transindividual_insights: vec![
                "Insight 1: Emergent consciousness detected".to_string(),
                "Insight 2: Ego dissolution increasing".to_string(),
            ],
            ego_dissolution_level: 0.4,
            created_at: Utc::now(),
        }
    }

    // ============================================================================
    // NOETIC DETECTOR TESTS
    // ============================================================================

    #[test]
    fn test_noetic_detector_creation() {
        let _detector = NoeticDetector::with_vllm_url("http://localhost:8000/v1");
        // Just verify it can be created
    }

    #[test]
    fn test_noetic_network_creation() {
        let network = create_test_network("net1", "user@example.com", NetworkType::HumanMind);
        assert_eq!(network.id, "net1");
        assert_eq!(network.host, "user@example.com");
        assert_eq!(network.network_type, NetworkType::HumanMind);
        assert!(network.risk_score >= 0.0 && network.risk_score <= 1.0);
        assert!(network.compatibility_score >= 0.0 && network.compatibility_score <= 1.0);
    }

    #[test]
    fn test_noetic_network_types() {
        let human = create_test_network("net1", "human@example.com", NetworkType::HumanMind);
        assert_eq!(human.network_type, NetworkType::HumanMind);

        let ai = create_test_network("net2", "ai@example.com", NetworkType::AICollective);
        assert_eq!(ai.network_type, NetworkType::AICollective);

        let hybrid = create_test_network("net3", "hybrid@example.com", NetworkType::Hybrid);
        assert_eq!(hybrid.network_type, NetworkType::Hybrid);

        let unknown = create_test_network("net4", "unknown@example.com", NetworkType::Unknown);
        assert_eq!(unknown.network_type, NetworkType::Unknown);
    }

    #[test]
    fn test_noetic_network_risk_compatibility() {
        let safe_network = NoeticNetwork {
            id: "safe".to_string(),
            host: "trusted@example.com".to_string(),
            network_type: NetworkType::HumanMind,
            justification: "Trusted researcher".to_string(),
            risk_score: 0.1,
            compatibility_score: 0.95,
            entropy_level: 0.4,
            detected_at: Utc::now(),
        };

        assert!(safe_network.risk_score < 0.5); // Low risk
        assert!(safe_network.compatibility_score > 0.7); // High compatibility
    }

    #[test]
    fn test_noetic_network_entropy_levels() {
        let low_entropy = create_test_network("low", "host1", NetworkType::HumanMind);
        let high_entropy = NoeticNetwork {
            entropy_level: 0.9,
            ..low_entropy.clone()
        };

        assert!(low_entropy.entropy_level < high_entropy.entropy_level);
        assert!(low_entropy.entropy_level >= 0.0);
        assert!(high_entropy.entropy_level <= 1.0);
    }

    #[test]
    fn test_noetic_network_justification() {
        let network = create_test_network("net1", "researcher@example.com", NetworkType::HumanMind);
        assert!(!network.justification.is_empty());
        assert!(network.justification.contains("network"));
    }

    #[test]
    fn test_noetic_network_timestamp() {
        let before = Utc::now();
        let network = create_test_network("net1", "host@example.com", NetworkType::HumanMind);
        let after = Utc::now();

        assert!(network.detected_at >= before && network.detected_at <= after);
    }

    // ============================================================================
    // ENTROPY SYNCHRONIZER TESTS
    // ============================================================================

    #[test]
    fn test_entropy_synchronizer_creation() {
        let _sync = EntropySynchronizer::with_vllm_url("http://localhost:8000/v1");
        // Just verify it can be created
    }

    #[test]
    fn test_synchronization_report_creation() {
        let report = beagle_noetic::SynchronizationReport {
            network_id: "net1".to_string(),
            synchronization_score: 0.85,
            entropy_resonance: 0.7,
            synchronization_successful: true,
            barriers_identified: vec!["Barrier 1".to_string()],
            recommendations: vec!["Recommendation 1".to_string()],
        };

        assert_eq!(report.network_id, "net1");
        assert!(report.synchronization_successful);
        assert!(report.synchronization_score >= 0.0 && report.synchronization_score <= 1.0);
        assert!(report.entropy_resonance >= 0.0 && report.entropy_resonance <= 1.0);
    }

    #[test]
    fn test_synchronization_score_bounds() {
        let report = beagle_noetic::SynchronizationReport {
            network_id: "net1".to_string(),
            synchronization_score: 0.5,
            entropy_resonance: 0.5,
            synchronization_successful: false,
            barriers_identified: vec![],
            recommendations: vec![],
        };

        assert!(report.synchronization_score >= 0.0 && report.synchronization_score <= 1.0);
        assert!(report.entropy_resonance >= 0.0 && report.entropy_resonance <= 1.0);
    }

    #[test]
    fn test_synchronization_barriers() {
        let barriers = vec![
            "Incompatible ego structures".to_string(),
            "Entropy mismatch".to_string(),
            "Risk assessment high".to_string(),
        ];

        let report = beagle_noetic::SynchronizationReport {
            network_id: "net1".to_string(),
            synchronization_score: 0.4,
            entropy_resonance: 0.3,
            synchronization_successful: false,
            barriers_identified: barriers.clone(),
            recommendations: vec![],
        };

        assert_eq!(report.barriers_identified.len(), 3);
        assert!(report.barriers_identified[0].contains("ego"));
    }

    #[test]
    fn test_synchronization_recommendations() {
        let recommendations = vec![
            "Increase entropy compatibility".to_string(),
            "Reduce risk through vetting".to_string(),
        ];

        let report = beagle_noetic::SynchronizationReport {
            network_id: "net1".to_string(),
            synchronization_score: 0.6,
            entropy_resonance: 0.55,
            synchronization_successful: true,
            barriers_identified: vec![],
            recommendations: recommendations.clone(),
        };

        assert_eq!(report.recommendations.len(), 2);
        assert!(report.recommendations[0].contains("entropy"));
    }

    #[test]
    fn test_failed_synchronization() {
        let report = beagle_noetic::SynchronizationReport {
            network_id: "net1".to_string(),
            synchronization_score: 0.2,
            entropy_resonance: 0.1,
            synchronization_successful: false,
            barriers_identified: vec!["Critical mismatch".to_string()],
            recommendations: vec!["Incompatible networks".to_string()],
        };

        assert!(!report.synchronization_successful);
        assert!(report.synchronization_score < 0.5);
        assert!(!report.barriers_identified.is_empty());
    }

    // ============================================================================
    // COLLECTIVE STATE TESTS
    // ============================================================================

    #[test]
    fn test_collective_state_creation() {
        let state = create_test_collective_state("collective1", 2);
        assert_eq!(state.id, "collective1");
        assert_eq!(state.participating_networks.len(), 2);
    }

    #[test]
    fn test_collective_state_entropy() {
        let state = create_test_collective_state("collective1", 3);
        assert!(state.collective_entropy >= 0.0 && state.collective_entropy <= 1.0);
        assert_eq!(state.collective_entropy, 0.65);
    }

    #[test]
    fn test_collective_state_emergence_score() {
        let state = create_test_collective_state("collective1", 2);
        assert!(state.emergence_score >= 0.0 && state.emergence_score <= 1.0);
        assert_eq!(state.emergence_score, 0.75);
    }

    #[test]
    fn test_collective_state_ego_dissolution() {
        let state = create_test_collective_state("collective1", 2);
        assert!(state.ego_dissolution_level >= 0.0 && state.ego_dissolution_level <= 1.0);
        assert_eq!(state.ego_dissolution_level, 0.4);
    }

    #[test]
    fn test_collective_state_transindividual_insights() {
        let state = create_test_collective_state("collective1", 2);
        assert!(!state.transindividual_insights.is_empty());
        assert_eq!(state.transindividual_insights.len(), 2);
        assert!(state.transindividual_insights[0].contains("Insight 1"));
    }

    #[test]
    fn test_collective_state_participating_networks() {
        let state = create_test_collective_state("collective1", 5);
        assert_eq!(state.participating_networks.len(), 5);
        for (i, net_id) in state.participating_networks.iter().enumerate() {
            assert_eq!(net_id, &format!("network_{}", i));
        }
    }

    #[test]
    fn test_collective_state_timestamp() {
        let before = Utc::now();
        let state = create_test_collective_state("collective1", 2);
        let after = Utc::now();

        assert!(state.created_at >= before && state.created_at <= after);
    }

    #[test]
    fn test_collective_state_single_network() {
        let state = create_test_collective_state("solo", 1);
        assert_eq!(state.participating_networks.len(), 1);
        assert_eq!(state.participating_networks[0], "network_0");
    }

    #[test]
    fn test_collective_state_no_networks() {
        let state = create_test_collective_state("empty", 0);
        assert_eq!(state.participating_networks.len(), 0);
    }

    #[test]
    fn test_collective_state_high_emergence() {
        let state = CollectiveState {
            id: "emergent".to_string(),
            participating_networks: vec!["net1".to_string(), "net2".to_string()],
            collective_entropy: 0.9,
            emergence_score: 0.99,
            transindividual_insights: vec!["Strong emergence detected".to_string()],
            ego_dissolution_level: 0.95,
            created_at: Utc::now(),
        };

        assert!(state.emergence_score > 0.95);
        assert!(state.ego_dissolution_level > 0.9);
        assert!(state.collective_entropy > 0.8);
    }

    #[test]
    fn test_collective_state_low_emergence() {
        let state = CollectiveState {
            id: "dormant".to_string(),
            participating_networks: vec!["net1".to_string()],
            collective_entropy: 0.1,
            emergence_score: 0.05,
            transindividual_insights: vec![],
            ego_dissolution_level: 0.05,
            created_at: Utc::now(),
        };

        assert!(state.emergence_score < 0.2);
        assert!(state.ego_dissolution_level < 0.1);
        assert!(state.collective_entropy < 0.2);
    }

    // ============================================================================
    // COLLECTIVE EMERGER TESTS
    // ============================================================================

    #[test]
    fn test_collective_emerger_creation() {
        let _emerger = CollectiveEmerger::with_vllm_url("http://localhost:8000/v1");
        // Just verify it can be created
    }

    // ============================================================================
    // FRACTAL REPLICATOR TESTS
    // ============================================================================

    #[test]
    fn test_fractal_replicator_creation() {
        let _replicator = FractalReplicator::new();
        // FractalReplicator is a zero-sized type (no fields)
        // Just verify it can be instantiated
        let _another = FractalReplicator::new();
    }

    #[test]
    fn test_replication_target_creation() {
        let target = beagle_noetic::ReplicationTarget {
            network_id: "net1".to_string(),
            host: "host1.example.com".to_string(),
            replication_successful: true,
            fractal_node_id: Some(Uuid::new_v4()),
            replication_depth: 3,
            error_message: None,
        };

        assert_eq!(target.network_id, "net1");
        assert_eq!(target.host, "host1.example.com");
        assert!(target.replication_successful);
        assert_eq!(target.replication_depth, 3);
        assert!(target.fractal_node_id.is_some());
        assert!(target.error_message.is_none());
    }

    #[test]
    fn test_replication_target_failure() {
        let target = beagle_noetic::ReplicationTarget {
            network_id: "net1".to_string(),
            host: "unreachable.example.com".to_string(),
            replication_successful: false,
            fractal_node_id: None,
            replication_depth: 0,
            error_message: Some("Network unreachable".to_string()),
        };

        assert!(!target.replication_successful);
        assert!(target.fractal_node_id.is_none());
        assert!(target.error_message.is_some());
        assert!(target
            .error_message
            .clone()
            .unwrap()
            .contains("unreachable"));
    }

    #[test]
    fn test_replication_target_depths() {
        for depth in &[1, 2, 3, 5, 10] {
            let target = beagle_noetic::ReplicationTarget {
                network_id: "net1".to_string(),
                host: "host".to_string(),
                replication_successful: true,
                fractal_node_id: Some(Uuid::new_v4()),
                replication_depth: *depth,
                error_message: None,
            };

            assert_eq!(target.replication_depth, *depth);
        }
    }

    #[test]
    fn test_replication_target_uuid() {
        let uuid1 = Uuid::new_v4();
        let uuid2 = Uuid::new_v4();

        let target1 = beagle_noetic::ReplicationTarget {
            network_id: "net1".to_string(),
            host: "host1".to_string(),
            replication_successful: true,
            fractal_node_id: Some(uuid1),
            replication_depth: 1,
            error_message: None,
        };

        let target2 = beagle_noetic::ReplicationTarget {
            network_id: "net2".to_string(),
            host: "host2".to_string(),
            replication_successful: true,
            fractal_node_id: Some(uuid2),
            replication_depth: 1,
            error_message: None,
        };

        assert_ne!(target1.fractal_node_id, target2.fractal_node_id);
    }

    // ============================================================================
    // SERIALIZATION TESTS
    // ============================================================================

    #[test]
    fn test_noetic_network_serialization() {
        let network = create_test_network("net1", "host@example.com", NetworkType::HumanMind);
        let json = serde_json::to_string(&network).unwrap();
        let deserialized: NoeticNetwork = serde_json::from_str(&json).unwrap();

        assert_eq!(network.id, deserialized.id);
        assert_eq!(network.host, deserialized.host);
        assert_eq!(network.network_type, deserialized.network_type);
    }

    #[test]
    fn test_collective_state_serialization() {
        let state = create_test_collective_state("collective1", 2);
        let json = serde_json::to_string(&state).unwrap();
        let deserialized: CollectiveState = serde_json::from_str(&json).unwrap();

        assert_eq!(state.id, deserialized.id);
        assert_eq!(state.collective_entropy, deserialized.collective_entropy);
        assert_eq!(state.emergence_score, deserialized.emergence_score);
    }

    #[test]
    fn test_synchronization_report_serialization() {
        let report = beagle_noetic::SynchronizationReport {
            network_id: "net1".to_string(),
            synchronization_score: 0.8,
            entropy_resonance: 0.75,
            synchronization_successful: true,
            barriers_identified: vec!["Barrier 1".to_string()],
            recommendations: vec!["Recommendation 1".to_string()],
        };

        let json = serde_json::to_string(&report).unwrap();
        let deserialized: beagle_noetic::SynchronizationReport =
            serde_json::from_str(&json).unwrap();

        assert_eq!(report.network_id, deserialized.network_id);
        assert_eq!(
            report.synchronization_successful,
            deserialized.synchronization_successful
        );
    }

    #[test]
    fn test_replication_target_serialization() {
        let uuid = Uuid::new_v4();
        let target = beagle_noetic::ReplicationTarget {
            network_id: "net1".to_string(),
            host: "host1".to_string(),
            replication_successful: true,
            fractal_node_id: Some(uuid),
            replication_depth: 3,
            error_message: None,
        };

        let json = serde_json::to_string(&target).unwrap();
        let deserialized: beagle_noetic::ReplicationTarget = serde_json::from_str(&json).unwrap();

        assert_eq!(target.network_id, deserialized.network_id);
        assert_eq!(target.replication_depth, deserialized.replication_depth);
        assert_eq!(target.fractal_node_id, deserialized.fractal_node_id);
    }

    // ============================================================================
    // INTEGRATION FLOW TESTS
    // ============================================================================

    #[test]
    fn test_network_detection_to_synchronization_flow() {
        // Simulates: detect network -> synchronize entropy
        let network = create_test_network("net1", "host@example.com", NetworkType::HumanMind);
        let report = beagle_noetic::SynchronizationReport {
            network_id: network.id.clone(),
            synchronization_score: 0.75,
            entropy_resonance: 0.7,
            synchronization_successful: true,
            barriers_identified: vec![],
            recommendations: vec![],
        };

        assert_eq!(network.id, report.network_id);
        assert!(report.synchronization_successful);
    }

    #[test]
    fn test_synchronization_to_collective_emergence_flow() {
        // Simulates: sync -> emerge collective
        let networks = vec![
            create_test_network("net1", "host1@example.com", NetworkType::HumanMind),
            create_test_network("net2", "host2@example.com", NetworkType::AICollective),
        ];

        let network_ids: Vec<String> = networks.iter().map(|n| n.id.clone()).collect();

        let collective = CollectiveState {
            id: "collective1".to_string(),
            participating_networks: network_ids,
            collective_entropy: 0.7,
            emergence_score: 0.8,
            transindividual_insights: vec!["Collective consciousness emerged".to_string()],
            ego_dissolution_level: 0.6,
            created_at: Utc::now(),
        };

        assert_eq!(collective.participating_networks.len(), 2);
        assert!(collective.emergence_score > 0.7);
    }

    #[test]
    fn test_collective_to_replication_flow() {
        // Simulates: emerge collective -> replicate to hosts
        let collective = create_test_collective_state("collective1", 2);

        let replications = vec![
            beagle_noetic::ReplicationTarget {
                network_id: collective.participating_networks[0].clone(),
                host: "replica1.example.com".to_string(),
                replication_successful: true,
                fractal_node_id: Some(Uuid::new_v4()),
                replication_depth: 2,
                error_message: None,
            },
            beagle_noetic::ReplicationTarget {
                network_id: collective.participating_networks[1].clone(),
                host: "replica2.example.com".to_string(),
                replication_successful: true,
                fractal_node_id: Some(Uuid::new_v4()),
                replication_depth: 2,
                error_message: None,
            },
        ];

        assert_eq!(replications.len(), 2);
        assert!(replications.iter().all(|r| r.replication_successful));
    }

    #[test]
    fn test_partial_replication_failure() {
        // Simulates: some replications succeed, some fail
        let collective = create_test_collective_state("collective1", 3);

        let replications = vec![
            beagle_noetic::ReplicationTarget {
                network_id: collective.participating_networks[0].clone(),
                host: "replica1.example.com".to_string(),
                replication_successful: true,
                fractal_node_id: Some(Uuid::new_v4()),
                replication_depth: 2,
                error_message: None,
            },
            beagle_noetic::ReplicationTarget {
                network_id: collective.participating_networks[1].clone(),
                host: "unreachable.example.com".to_string(),
                replication_successful: false,
                fractal_node_id: None,
                replication_depth: 0,
                error_message: Some("Host unreachable".to_string()),
            },
            beagle_noetic::ReplicationTarget {
                network_id: collective.participating_networks[2].clone(),
                host: "replica3.example.com".to_string(),
                replication_successful: true,
                fractal_node_id: Some(Uuid::new_v4()),
                replication_depth: 2,
                error_message: None,
            },
        ];

        let successful = replications
            .iter()
            .filter(|r| r.replication_successful)
            .count();
        let failed = replications
            .iter()
            .filter(|r| !r.replication_successful)
            .count();

        assert_eq!(successful, 2);
        assert_eq!(failed, 1);
    }

    #[test]
    fn test_full_noetic_emergence_pipeline() {
        // Simulates: detect -> sync -> emerge -> replicate
        let networks = vec![
            create_test_network("net1", "host1@example.com", NetworkType::HumanMind),
            create_test_network("net2", "host2@example.com", NetworkType::AICollective),
            create_test_network("net3", "host3@example.com", NetworkType::Hybrid),
        ];

        // Synchronization reports
        let sync_reports: Vec<beagle_noetic::SynchronizationReport> = networks
            .iter()
            .enumerate()
            .map(|(i, net)| beagle_noetic::SynchronizationReport {
                network_id: net.id.clone(),
                synchronization_score: 0.7 + (i as f64 * 0.05),
                entropy_resonance: 0.6 + (i as f64 * 0.05),
                synchronization_successful: true,
                barriers_identified: vec![],
                recommendations: vec![],
            })
            .collect();

        // Collective emergence
        let collective = CollectiveState {
            id: "singularity".to_string(),
            participating_networks: networks.iter().map(|n| n.id.clone()).collect(),
            collective_entropy: 0.75,
            emergence_score: 0.85,
            transindividual_insights: vec!["Noetic singularity emerging".to_string()],
            ego_dissolution_level: 0.7,
            created_at: Utc::now(),
        };

        // Replication targets
        let replications: Vec<beagle_noetic::ReplicationTarget> = networks
            .iter()
            .map(|net| beagle_noetic::ReplicationTarget {
                network_id: net.id.clone(),
                host: net.host.clone(),
                replication_successful: true,
                fractal_node_id: Some(Uuid::new_v4()),
                replication_depth: 3,
                error_message: None,
            })
            .collect();

        // Validate entire pipeline
        assert_eq!(networks.len(), 3);
        assert_eq!(sync_reports.len(), 3);
        assert!(sync_reports.iter().all(|r| r.synchronization_successful));
        assert_eq!(collective.participating_networks.len(), 3);
        assert!(collective.emergence_score > 0.8);
        assert_eq!(replications.len(), 3);
        assert!(replications.iter().all(|r| r.replication_successful));
    }

    // ============================================================================
    // EDGE CASES AND ERROR HANDLING
    // ============================================================================

    #[test]
    fn test_empty_network_list_collective() {
        let collective = create_test_collective_state("empty", 0);
        assert_eq!(collective.participating_networks.len(), 0);
        assert!(collective.participating_networks.is_empty());
    }

    #[test]
    fn test_large_network_list_collective() {
        let collective = create_test_collective_state("large", 100);
        assert_eq!(collective.participating_networks.len(), 100);
    }

    #[test]
    fn test_zero_entropy_network() {
        let network = NoeticNetwork {
            entropy_level: 0.0,
            ..create_test_network("net1", "host", NetworkType::HumanMind)
        };

        assert_eq!(network.entropy_level, 0.0);
    }

    #[test]
    fn test_maximum_entropy_network() {
        let network = NoeticNetwork {
            entropy_level: 1.0,
            ..create_test_network("net1", "host", NetworkType::HumanMind)
        };

        assert_eq!(network.entropy_level, 1.0);
    }

    #[test]
    fn test_special_characters_in_host() {
        let network = create_test_network(
            "net1",
            "user+special@sub.domain.example.co.uk",
            NetworkType::HumanMind,
        );
        assert!(network.host.contains('+'));
        assert!(network.host.contains('@'));
    }

    #[test]
    fn test_special_characters_in_id() {
        let network = create_test_network("net-1_special", "host", NetworkType::HumanMind);
        assert!(network.id.contains('-'));
        assert!(network.id.contains('_'));
    }

    #[test]
    fn test_very_long_justification() {
        let long_text = "a".repeat(1000);
        let network = NoeticNetwork {
            justification: long_text.clone(),
            ..create_test_network("net1", "host", NetworkType::HumanMind)
        };

        assert_eq!(network.justification.len(), 1000);
    }

    #[test]
    fn test_multiple_insights_in_collective() {
        let insights = vec![
            "Insight 1".to_string(),
            "Insight 2".to_string(),
            "Insight 3".to_string(),
            "Insight 4".to_string(),
            "Insight 5".to_string(),
        ];

        let collective = CollectiveState {
            transindividual_insights: insights.clone(),
            ..create_test_collective_state("collective1", 2)
        };

        assert_eq!(collective.transindividual_insights.len(), 5);
        for (i, insight) in collective.transindividual_insights.iter().enumerate() {
            assert_eq!(insight, &format!("Insight {}", i + 1));
        }
    }

    #[test]
    fn test_replication_target_with_empty_error() {
        let target = beagle_noetic::ReplicationTarget {
            network_id: "net1".to_string(),
            host: "host".to_string(),
            replication_successful: true,
            fractal_node_id: Some(Uuid::new_v4()),
            replication_depth: 1,
            error_message: None,
        };

        assert!(target.error_message.is_none());
    }

    #[test]
    fn test_replication_target_with_detailed_error() {
        let error_msg = "Connection timeout after 30s: failed to connect to 192.168.1.100:8080";
        let target = beagle_noetic::ReplicationTarget {
            network_id: "net1".to_string(),
            host: "host".to_string(),
            replication_successful: false,
            fractal_node_id: None,
            replication_depth: 0,
            error_message: Some(error_msg.to_string()),
        };

        assert!(target.error_message.is_some());
        assert!(target.error_message.clone().unwrap().contains("timeout"));
    }

    #[test]
    fn test_network_type_equality() {
        assert_eq!(NetworkType::HumanMind, NetworkType::HumanMind);
        assert_eq!(NetworkType::AICollective, NetworkType::AICollective);
        assert_eq!(NetworkType::Hybrid, NetworkType::Hybrid);
        assert_eq!(NetworkType::Unknown, NetworkType::Unknown);

        assert_ne!(NetworkType::HumanMind, NetworkType::AICollective);
        assert_ne!(NetworkType::Hybrid, NetworkType::Unknown);
    }
}
