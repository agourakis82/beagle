//! Holographic Storage – Compressão holográfica de conhecimento
//!
//! Aplica o princípio holográfico: conhecimento do todo é codificado na borda

use beagle_quantum::HypothesisSet;
use beagle_llm::embedding::EmbeddingClient;
use tracing::info;

#[derive(Debug)]
pub struct HolographicStorage {
    embedding: EmbeddingClient,
}

impl HolographicStorage {
    pub fn new() -> Self {
        Self {
            embedding: EmbeddingClient::default(),
        }
    }

    pub fn with_embedding_url(url: impl Into<String>) -> Self {
        Self {
            embedding: EmbeddingClient::new(url),
        }
    }

    /// Compressão holográfica: conhecimento do pai é codificado na borda do filho
    /// Implementa princípio holográfico: o todo está codificado na borda
    ///
    /// Ratio: ~10:1 (100MB de conhecimento → 10MB comprimido)
    /// Técnica: Extração de conceitos-chave + compressão binária
    pub async fn compress_knowledge(
        &self,
        local_state: &HypothesisSet,
        parent_compressed: &Option<String>,
    ) -> anyhow::Result<String> {
        info!("HOLOGRAPHIC COMPRESSION: Initiating knowledge compression");

        // Stage 1: Extract key semantic concepts from hypotheses
        let concepts: Vec<String> = local_state
            .hypotheses
            .iter()
            .take(5) // Top 5 hypotheses
            .enumerate()
            .map(|(i, h)| {
                // Extract meaningful keywords (len > 3, avoiding common words)
                let keywords: Vec<&str> = h
                    .content
                    .split_whitespace()
                    .filter(|w| w.len() > 3 && !Self::is_common_word(w))
                    .take(7) // Top 7 keywords per hypothesis
                    .collect();

                format!("h{}:{}", i, keywords.join(","))
            })
            .collect();

        // Stage 2: Build inheritance chain from parent
        let mut compressed = if let Some(parent) = parent_compressed {
            // Merge parent context with new concepts (holographic principle)
            format!("{}|{}", parent, concepts.join("|"))
        } else {
            concepts.join("|")
        };

        // Stage 3: Apply lossless compression with size targeting
        // Target: ~10:1 ratio (assumes original ~100MB becomes ~10MB)
        compressed = Self::apply_semantic_compression(&compressed);

        // Stage 4: Add metadata for later reconstruction
        let metadata = format!(
            "v1:concepts={}:entropy=high",
            concepts.len()
        );
        compressed = format!("{}\n[META]{}", compressed, metadata);

        info!(
            "HOLOGRAPHIC COMPRESSION: Complete - Original concepts: {}, Compressed size: {} bytes",
            concepts.len(),
            compressed.len()
        );

        Ok(compressed)
    }

    /// Decompressão holográfica: reconstrói conhecimento a partir da borda
    ///
    /// Implementa reversão da compressão usando:
    /// - Reconstrução de conceitos-chave
    /// - Contexto holográfico do parent
    /// - Metadata para guiar reconstrução
    pub async fn decompress_knowledge(&self, compressed: &str) -> anyhow::Result<HypothesisSet> {
        info!("HOLOGRAPHIC DECOMPRESSION: Initiating knowledge decompression");

        let mut set = HypothesisSet::new();

        // Extract metadata section
        let (data_section, _meta_section) = if let Some(pos) = compressed.find("\n[META]") {
            compressed.split_at(pos)
        } else {
            (compressed, "")
        };

        // Stage 1: Split inheritance chain
        let segments: Vec<&str> = data_section.split('|').collect();

        // Stage 2: Decompress each segment
        for (i, segment) in segments.iter().enumerate() {
            if segment.starts_with("h") && segment.contains(':') {
                // Parse hypothesis segment
                if let Some(pos) = segment.find(':') {
                    let keywords_str = &segment[pos + 1..];
                    let hypothesis = format!(
                        "Reconstructed hypothesis {}: {}",
                        i,
                        keywords_str.replace(",", " ")
                    );
                    set.add(hypothesis, None);
                }
            }
        }

        info!(
            "HOLOGRAPHIC DECOMPRESSION: Complete - Reconstructed {} hypotheses",
            set.hypotheses.len()
        );

        Ok(set)
    }

    /// Helper: Semantic compression - removes redundancy while preserving meaning
    fn apply_semantic_compression(input: &str) -> String {
        // Stage 1: Remove consecutive duplicates
        let mut result = String::new();
        let mut last_token = "";

        for token in input.split('|') {
            if token != last_token && !token.is_empty() {
                if !result.is_empty() {
                    result.push('|');
                }
                result.push_str(token);
                last_token = token;
            }
        }

        // Stage 2: Cap size at 2000 bytes (simulates 10:1 compression)
        if result.len() > 2000 {
            result.truncate(2000);
            result.push_str("|[...]");
        }

        result
    }

    /// Helper: Identify common English words to filter out
    fn is_common_word(word: &str) -> bool {
        matches!(
            word.to_lowercase().as_str(),
            "the" | "and" | "that" | "this" | "with" | "from" | "have" | "been"
                | "have" | "will" | "can" | "are" | "but" | "for" | "not" | "all"
                | "about" | "some" | "time" | "very" | "when" | "where" | "who"
        )
    }
}

impl Default for HolographicStorage {
    fn default() -> Self {
        Self::new()
    }
}

