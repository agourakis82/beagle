#[cfg(test)]
mod tests {
    use beagle_workspace::*;
    use tokio_test;

    #[tokio::test]
    async fn test_kec_engine() {
        let kec = Kec3Engine::new();
        let graph_data = vec![1.0; 100];
        let result = kec.compute_all_metrics(&graph_data).await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_embeddings() {
        let emb = EmbeddingManager::new(EmbeddingModel::Nomic);
        let texts = vec!["test".to_string()];
        let result = emb.encode(&texts).await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_pbpk_platform() {
        let pbpk = PBPKPlatform::new();
        let result = pbpk.encode_multimodal("CCO").await;
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_heliobiology() {
        let helio = HeliobiologyPlatform::new();
        let history = vec![1.0f32; 72];
        let result = helio.forecast_kairos(&history).await;
        assert!(result.is_ok());
    }
}

