# BEAGLE Auto-Publish - Publicação Automática no arXiv

Publica papers automaticamente no arXiv com DOI real, PDF bonito, metadata perfeito.

## 🚀 Setup

### 1. Instalar dependências

```bash
# Pandoc (converte markdown → PDF)
sudo apt install pandoc texlive-xetex  # Linux
brew install pandoc basictex           # macOS
```

### 2. Configurar API Token

```bash
export ARXIV_API_TOKEN="seu-token-aqui"
# Pega em: arxiv.org → settings → API
```

## 📝 Como Usar

### Publicação Automática

```rust
use beagle_publish::publish_to_arxiv;

let doi = publish_to_arxiv(
    "Título do Paper",
    "Abstract completo aqui",
    "paper_final.md",
    "cs.AI q-bio.NC physics.bio-ph"
).await?;

println!("✅ Paper publicado — DOI: {}", doi);
```

### Auto-publish quando score > 98

```rust
use beagle_publish::auto_publish_if_ready;

if let Some(doi) = auto_publish_if_ready(
    &title,
    &abstract_text,
    "paper_final.md",
    score
).await? {
    println!("✅ Paper publicado automaticamente — DOI: {}", doi);
}
```

## 🔍 Validação Antes de Publicar

```rust
use beagle_arxiv_validate::ArxivValidator;

let validator = ArxivValidator::new();
let issues = validator.validate_markdown("paper_final.md")?;

if issues[0] == "VALIDADO" {
    publish_to_arxiv(...).await?;
} else {
    println!("❌ Paper não passou na validação:");
    for issue in issues {
        println!("  - {}", issue);
    }
}
```

## 📊 Funcionalidades

- ✅ Gera PDF bonito com pandoc + LaTeX
- ✅ Valida PDF antes de submeter (tamanho, formato)
- ✅ Upload automático pro arXiv
- ✅ Gera DOI real
- ✅ Metadata perfeito
- ✅ Auto-publish quando score > 98

---

**100% Automático. Zero Trabalho Manual.**

