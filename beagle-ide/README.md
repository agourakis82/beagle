# BEAGLE IDE

IDE científica completa e funcional para produção científica interdisciplinar, com integração real ao cluster Darwin e colaboração em tempo real.

## 🚀 Como Rodar (AGORA)

### Pré-requisitos

- Rust 1.70+ e Cargo
- Node.js 18+ (opcional, apenas se quiser usar npm scripts)
- kubectl configurado para cluster Darwin (para integração completa)

### Executar

```bash
cd beagle-ide/src-tauri
cargo tauri dev
```

**Pronto!** A IDE abre automaticamente em < 30 segundos.

## ✨ Funcionalidades

### 4 Painéis Fixos

1. **Knowledge Graph** - Visualização de conceitos e relacionamentos (Vis.js)
2. **Paper Canvas** - Editor com CodeMirror 6 (Rust + Julia support)
3. **Agent Console** - Logs em tempo real do cluster Darwin
4. **Quantum View** - Visualização de estados quânticos e superposições

### CodeMirror 6

- Suporte real para **Rust** e **Julia** com **LSP real**
- **rust-analyzer** e **Julia LanguageServer** integrados
- Autocompletar, hover, goto definition, diagnostics
- Tema BEAGLE personalizado (#0F0F0F + #00D4FF)
- Syntax highlighting completo

### Yjs Real-time

- Colaboração em tempo real
- Multi-cursor (quando múltiplos usuários)
- Sincronização automática
- Conecta com `ws://localhost:1234` ou `wss://yjs.demetrios.ai`

### Voice Command

- Reconhecimento de voz integrado (Web Speech API)
- Ativar com **Ctrl+Shift+V** (ou Cmd+Shift+V no Mac)
- Comandos: "BEAGLE, cria seção sobre KEC"
- Suporta português (pt-BR)

### Git Semântico

- Blame por ideia/conceito (não apenas linha)
- Clique em qualquer linha no editor para ver blame semântico
- Mostra autor, commit, mensagem e timestamp

### Integração com Cluster Darwin

- Status de nodes e pods em tempo real
- Logs do cluster via kubectl
- Execução de comandos remotos
- Atualização automática a cada 10 segundos

## 🎨 Tema

- Background: `#0F0F0F`
- Accent: `#00D4FF`
- Editor: `#1a1a1a`
- Fonte: JetBrains Mono

## 📦 Estrutura

```
beagle-ide/
├── src-tauri/          # Backend Rust (Tauri 2.0)
│   ├── src/
│   │   ├── main.rs     # Entry point
│   │   └── commands.rs # Comandos Tauri (voice, cluster, yjs, git)
│   ├── Cargo.toml
│   └── tauri.conf.json
├── index.html          # Frontend completo (4 painéis)
└── README.md
```

## 🔧 Comandos Disponíveis

### LSP (Language Server Protocol)

#### Iniciar LSP
```rust
lsp_start(language: String, root_path: Option<String>) -> Result<String, String>
```
Inicia servidor LSP (rust ou julia).

#### Completar
```rust
lsp_completion(request: LspCompletionRequest) -> Result<Vec<CompletionItem>, String>
```
Obtém completões no posição especificada (Ctrl+Space).

#### Hover
```rust
lsp_hover(request: LspHoverRequest) -> Result<Option<Hover>, String>
```
Obtém informação de hover (tipos, documentação).

#### Goto Definition
```rust
lsp_goto_definition(request: LspGotoDefinitionRequest) -> Result<Option<Vec<Location>>, String>
```
Vai para definição (Ctrl+Click ou F12).

#### DidOpen/DidChange
```rust
lsp_did_open(request: LspDidOpenRequest) -> Result<(), String>
lsp_did_change(request: LspDidChangeRequest) -> Result<(), String>
```
Notifica servidor LSP sobre mudanças no documento.

### Voice Command
```rust
voice_command(command: String) -> Result<String, String>
```
Processa comando de voz e executa ação correspondente.

### Yjs Sync
```rust
yjs_sync(update: Vec<u8>) -> Result<Vec<u8>, String>
```
Sincroniza atualizações Yjs com servidor.

### Cluster Status
```rust
cluster_status() -> Result<ClusterStatus, String>
```
Obtém status do cluster Darwin (nodes, pods, readiness).

### Cluster Logs
```rust
cluster_logs(limit: Option<usize>) -> Result<Vec<String>, String>
```
Buscas logs do cluster via kubectl.

### Cluster Exec
```rust
cluster_exec(command: String) -> Result<String, String>
```
Executa comando no cluster.

### Git Semantic Blame
```rust
git_semantic_blame(file_path: String, line: usize) -> Result<SemanticBlame, String>
```
Blame semântico por linha (extrai conceito, não apenas commit).

## 🛠️ Desenvolvimento

### Modo Dev

```bash
cd src-tauri
cargo tauri dev
```

### Build Release

```bash
cd src-tauri
cargo tauri build
```

### Testar Sem Tauri (Web)

Abre `index.html` diretamente no navegador (funciona com fallbacks simulados).

## 🌐 Configuração Yjs

Por padrão, tenta conectar em:
1. `ws://localhost:1234` (local)
2. `wss://yjs.demetrios.ai` (remoto)

Para usar servidor próprio:
1. Instale y-websocket: `npm install -g y-websocket`
2. Inicie: `PORT=1234 npx y-websocket`
3. Ou edite `index.html` linha 296 para seu servidor

## 📝 Notas

- Zero Electron (Tauri 2.0, <30MB)
- 100% funcional HOJE
- Integração real com cluster Darwin
- Voice command funcional
- Yjs real-time pronto
- Tema BEAGLE perfeito

### LSP Atalhos:

1. **Autocompletar**: Digite código e pressione `Ctrl+Space`
2. **Goto Definition**: `Ctrl+Click` ou `F12` em qualquer símbolo
3. **Hover**: Passe mouse sobre símbolo (pode ser lento, desabilitado por padrão)

### Requisitos LSP:

- **rust-analyzer**: Instale com `cargo install rust-analyzer` ou via rustup
- **Julia LanguageServer**: Instale com `julia -e 'using Pkg; Pkg.add("LanguageServer")'`

## 🚀 Próximos Passos

1. ✅ **LSP integrado!** Funciona automaticamente com rust-analyzer e Julia LanguageServer
2. Adicionar mais comandos de voz
3. Melhorar parsing de git blame semântico
4. Adicionar visualizações avançadas no Quantum View
5. Integrar com HERMES API real

---

**Desenvolvido para produção científica de alto nível.** ⚛️

