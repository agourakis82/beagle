# BEAGLE Bilingual - 100% Automático

Todo paper, tweet, thread, LinkedIn post e resposta do BEAGLE sai bilíngue automático (português + inglês perfeito).

## 🚀 Como Usar

### Básico

```rust
use beagle_bilingual::to_bilingual;

let bilingual = to_bilingual("Este é um texto em português").await?;
println!("PT: {}", bilingual.pt);
println!("EN: {}", bilingual.en);
```

### No Loop Adversarial (quando score > 98)

```rust
use beagle_serendipity::integrate_bilingual_publish;

if score > 98.0 {
    integrate_bilingual_publish(
        &title_pt,
        &abstract_pt,
        &paper_url,
        score
    ).await?;
}
```

### Twitter Thread Bilíngue

```rust
use beagle_bilingual::BeagleTwitter;

let twitter = BeagleTwitter::new("TEU_BEARER_TOKEN");
twitter.thread_paper(&title_pt, &abstract_pt, &paper_url).await?;
```

## ⚙️ Configuração

```bash
# Grok API Key (obrigatório)
export GROK_API_KEY="xai-tua-key"

# Twitter Bearer Token (opcional, para postar automaticamente)
export TWITTER_BEARER_TOKEN="teu-bearer-token"
```

## 📝 Funcionalidades

- ✅ Tradução automática PT → EN (acadêmico perfeito)
- ✅ Tradução automática EN → PT (acadêmico perfeito)
- ✅ Detecção automática de idioma
- ✅ Geração de thread Twitter bilíngue
- ✅ Integração com loop adversarial
- ✅ Fallback gracioso (retorna original se falhar)

## 🎯 Exemplo Completo

```rust
use beagle_bilingual::{to_bilingual, BeagleTwitter};

// Traduz texto
let bilingual = to_bilingual("Este é um paper sobre KEC 3.0").await?;

// Posta thread bilíngue
let twitter = BeagleTwitter::new(env::var("TWITTER_BEARER_TOKEN")?);
twitter.thread_paper(
    "Título do Paper",
    "Resumo do paper...",
    "https://arxiv.org/abs/..."
).await?;
```

---

**100% Automático. Zero Configuração. Roda Hoje.**

