use crate::measurement::CollapseStrategy;
use crate::superposition::HypothesisSet;
use async_trait::async_trait;

#[async_trait]
pub trait QuantumReasoner {
    /// Recebe uma pergunta aberta e retorna múltiplas hipóteses em superposição
    async fn superposition_reason(&self, query: &str) -> anyhow::Result<HypothesisSet>;

    /// Aplica interferência (evidências reforçam ou destroem caminhos)
    async fn interfere(&self, set: &mut HypothesisSet, evidence: &str) -> anyhow::Result<()>;

    /// Colapsa para a melhor hipótese (ou mantém superposição se confiança baixa)
    async fn measure(
        &self,
        set: HypothesisSet,
        strategy: CollapseStrategy,
    ) -> anyhow::Result<String>;
}
