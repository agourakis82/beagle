# A Sessão à altura do chat — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Sessão do Mission Control mostra o custo por turno, para de mentir sobre o efeito do `/steer`, e deixa de oferecer caixa de prompt em lane que devolve 404.

**Architecture:** Um campo tipado novo no `loomd` (`aceita`) atravessa até a tela e decide três comportamentos. O resto é acabamento sobre código que já desenha os seis tipos de passo. **A Sessão não é reescrita.**

**Tech Stack:** Rust (axum 0.7, serde) no `crates/loomd`; Swift 6 / SwiftUI no `beagle-ios/BeagleSuite`, testes por `swift test`.

**Spec:** [2026-08-11-sessao-custo-fala-steer-design.md](../specs/2026-08-11-sessao-custo-fala-steer-design.md)

## Global Constraints

- **DOIS repositórios, e errar isso destrói trabalho.**
  - Rust: `/home/devsounio/beagle`, branch `reconcile/unify-beagle`. Cargo roda **de dentro de `crates/loomd`** (o crate está fora do workspace do monorepo).
  - Swift: **no Mac**, `ssh -o StrictHostKeyChecking=no demetriosagourakis@100.91.184.41`, repo `~/Developer/beagle`, branch `integration/mission-control-ui`. **O fonte do Mac é o vivo** — a cópia em `/home/devsounio/beagle/beagle-ios` está 6 commits atrás e um `rsync` na direção errada destrói o conserto de keepalive. Use o alias por IP; `ssh mac` falha por host-key.
- **Testes Rust inline** em `#[cfg(test)] mod tests`; não existe diretório `tests/` no crate e não se cria.
- **Testes Swift** em `Tests/BeagleCoreTests/` (alvo `BeagleCoreTests`, já existe com 8+ arquivos). Rodar: `swift test --package-path beagle-ios/BeagleSuite`.
- Antes de cada commit Rust: `cargo fmt && cargo clippy --all-targets && cargo test` de dentro de `crates/loomd`. Hoje: **89 testes, clippy zero**. Nenhum dos dois pode regredir.
- **Mutação obrigatória** em toda asserção nova, e o vermelho tem de vir de **asserção**. ⚠️ Vermelho por **erro de compilação não conta** — prova que o compilador cobra algo, não que o teste pega o defeito. Se sua mutação não compilar, **reescreva a mutação**. Registre no relatório, por mutação, se o vermelho foi por asserção.
- **Um commit por tarefa**, no repo correspondente. Outra sessão commita na branch do t560: devolva hashes **exatos**, nunca `HEAD~1`.
- Não tocar na aba Terminais, no layout geral, nem no `codex.rs`.

### Correção ao spec, já verificada

O §5 do spec lista "erro de protocolo visível" como item de acabamento. **Já está feito no lado Swift:** `SessionStore.passo(de:)` tem `case "error": return .failure(...)`. A lacuna era só backend, e foi consertada hoje (`d7e8e880`, `from_acp_error`). **Não há trabalho nesse item** — confirme e siga.

---

## File Structure

| arquivo | responsabilidade | repo |
|---|---|---|
| `crates/loomd/src/trama.rs` (modificar) | `enum Aceita` + campo em `LaneState` | t560 |
| `crates/loomd/src/main.rs` (modificar) | derivar `Aceita` de qual mapa a lane veio | t560 |
| `BeagleCore/Fleet/LaneState.swift` (modificar) | `Aceita` decodificado, **não inferido**; comentário de dívida em `isAbsent` | Mac |
| `BeagleCore/Fleet/SessionStore.swift` (modificar) | `SessionStep.uso`, `UsoDoTurno`, `rotuloDeGuiar` | Mac |
| `BeagleWorkbenchKit/Fleet/SessionView.swift` (modificar) | rodapé, ferramenta recolhida, diff, caixa condicional | Mac |
| `BeagleWorkbenchKit/Fleet/FrotaView.swift` (modificar) | acumulado no `LaneCard` | Mac |
| `Tests/BeagleCoreTests/SessaoUsoTests.swift` (criar) | testes puros de uso/rótulo/decodificação | Mac |

---

## Task 1: `Aceita` no loomd

**Files:**
- Modify: `crates/loomd/src/trama.rs` (struct `LaneState`, por volta da linha 37)
- Modify: `crates/loomd/src/main.rs` (os três laços de lane em `main()`)

**Interfaces:**
- Consumes: `parse_lanes(spec, padrao) -> Vec<(String,String)>`, já existente e testada.
- Produces:
  ```rust
  pub enum Aceita { Redireciona, Enfileira, SomenteLeitura }   // serde snake_case
  pub fn aceita_da_lane(codex: &[(String,String)], acp: &[(String,String)],
                        tails: &[(String,String)], lane: &str) -> Option<Aceita>;
  // LaneState ganha: pub aceita: Option<Aceita>
  ```

- [ ] **Step 1: Escrever o teste que falha**

Em `crates/loomd/src/trama.rs`, dentro do `#[cfg(test)] mod tests`:

```rust
    /// 🚨 O que a lane ACEITA não se deduz do NOME. `claude-1` (tail, só leitura) e `claude-4`
    /// (ACP, dirigível) têm o mesmo prefixo e comportamentos OPOSTOS: `/prompt` na primeira
    /// devolve 404. O cliente lê este campo; nunca infere do sid.
    #[test]
    fn aceita_sai_de_qual_conjunto_a_lane_veio() {
        let codex = vec![("codex-4".to_string(), "/wt/codex-4".to_string())];
        let acp = vec![("claude-4".to_string(), "/wt/claude-4".to_string())];
        let tails = vec![("claude-1".to_string(), "/dir".to_string())];

        assert_eq!(aceita_da_lane(&codex, &acp, &tails, "codex-4"), Some(Aceita::Redireciona));
        assert_eq!(aceita_da_lane(&codex, &acp, &tails, "claude-4"), Some(Aceita::Enfileira));
        assert_eq!(aceita_da_lane(&codex, &acp, &tails, "claude-1"), Some(Aceita::SomenteLeitura));
        assert_eq!(aceita_da_lane(&codex, &acp, &tails, "nao-existe"), None);
    }

    /// O prefixo do nome NÃO decide. Duas lanes `claude-*` em conjuntos diferentes têm de sair
    /// diferentes — é este teste que impede alguém de "simplificar" para `sid.starts_with`.
    #[test]
    fn duas_lanes_do_mesmo_prefixo_podem_aceitar_coisas_opostas() {
        let acp = vec![("claude-4".to_string(), "/wt".to_string())];
        let tails = vec![("claude-1".to_string(), "/dir".to_string())];
        let a = aceita_da_lane(&[], &acp, &tails, "claude-4");
        let b = aceita_da_lane(&[], &acp, &tails, "claude-1");
        assert_ne!(a, b, "mesmo prefixo, capacidades opostas");
    }

    #[test]
    fn aceita_serializa_em_snake_case() {
        let j = serde_json::to_string(&Aceita::SomenteLeitura).unwrap();
        assert_eq!(j, "\"somente_leitura\"");
    }
```

- [ ] **Step 2: Rodar e ver falhar**

```bash
cd /home/devsounio/beagle/crates/loomd
cargo test aceita 2>&1 | tail -12
```

Esperado: FAIL — `cannot find type Aceita` / `cannot find function aceita_da_lane`.

- [ ] **Step 3: Implementar**

Em `crates/loomd/src/trama.rs`, antes de `pub struct LaneState`:

```rust
/// O que ESTA lane aceita. A tela lê isto para nunca oferecer o que devolve 404, e para dizer
/// "enfileirar" onde enfileira e "redirecionar" onde redireciona.
///
/// 🚨 NÃO se deduz do nome. `claude-1` é tail (só leitura) e `claude-4` é ACP (dirigível) — mesmo
/// prefixo, comportamentos opostos. Deduzir do sid é o defeito que este tipo existe para impedir.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Aceita {
    /// codex: `turn/steer` REDIRECIONA o turno em curso.
    Redireciona,
    /// ACP: não há steer; `promptQueueing` ENFILEIRA para depois.
    Enfileira,
    /// tail: o loomd só LÊ o transcript. `/prompt` e `/steer` devolvem 404.
    SomenteLeitura,
}

/// De qual conjunto a lane veio. A guarda de sobreposição em `main()` já garante que ela está em
/// no máximo um, então a ordem de teste aqui não pode produzir ambiguidade.
pub fn aceita_da_lane(
    codex: &[(String, String)],
    acp: &[(String, String)],
    tails: &[(String, String)],
    lane: &str,
) -> Option<Aceita> {
    let tem = |v: &[(String, String)]| v.iter().any(|(l, _)| l == lane);
    if tem(codex) {
        Some(Aceita::Redireciona)
    } else if tem(acp) {
        Some(Aceita::Enfileira)
    } else if tem(tails) {
        Some(Aceita::SomenteLeitura)
    } else {
        None
    }
}
```

E no `struct LaneState`, junto dos outros campos opcionais:

```rust
    /// O que esta lane aceita — ver `Aceita`. `None` só antes de a lane ser declarada.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub aceita: Option<Aceita>,
```

- [ ] **Step 4: Ligar em `main()`**

Em `crates/loomd/src/main.rs`, depois de os três `parse_lanes` existirem e **depois** da guarda de sobreposição, anote a capacidade de cada lane declarada. `Trama::declarar(lane)` passa a receber a capacidade:

```rust
// A capacidade é registrada junto da declaração: a lane aparece no board já dizendo o que aceita,
// e não há janela em que a tela mostre botão sem saber se ele funciona.
for (l, c) in &lanes { trama.declarar_com(l, aceita_da_lane(&lanes, &acp_lanes, &tails, l)); … }
```

Ajuste `Trama::declarar` para `declarar_com(&self, lane: &str, aceita: Option<Aceita>)`, mantendo `declarar(lane)` como `declarar_com(lane, None)` para não quebrar chamadas existentes.

- [ ] **Step 5: Rodar e ver passar**

```bash
cd /home/devsounio/beagle/crates/loomd
cargo fmt && cargo clippy --all-targets 2>&1 | grep -cE "^warning|^error" | sed 's/^/avisos+erros: /'
cargo test 2>&1 | grep -E "^test result"
```

Esperado: clippy **0**, e `92 passed` (89 + 3 novos).

- [ ] **Step 6: Mutação**

```bash
cd /home/devsounio/beagle/crates/loomd
cp src/trama.rs /tmp/tr.bak
# Mutação: deduzir do prefixo do nome, que é o defeito que o tipo existe para impedir
python3 - <<'PY'
p="src/trama.rs"; s=open(p).read()
a='    let tem = |v: &[(String, String)]| v.iter().any(|(l, _)| l == lane);'
assert a in s, "ancora"
s=s.replace(a,'    let tem = |v: &[(String, String)]| v.iter().any(|(l, _)| l.split(\'-\').next() == lane.split(\'-\').next());',1)
open(p,"w").write(s)
PY
cargo test duas_lanes_do_mesmo_prefixo 2>&1 | grep -E "^test result"   # PRECISA falhar
cp /tmp/tr.bak src/trama.rs
cargo test 2>&1 | grep -E "^test result"
```

Se ficar verde, o teste é teatral — conserte o teste antes de seguir.

- [ ] **Step 7: Commit**

```bash
cd /home/devsounio/beagle
git add crates/loomd/src/trama.rs crates/loomd/src/main.rs
git commit -m "feat(loomd): campo `aceita` — o que a lane aceita, tipado, nao deduzido do nome

A tela precisa saber ANTES do clique se o gesto redireciona, enfileira ou nem
existe. Deduzir do sid nao serve: claude-1 (tail, so leitura) e claude-4 (ACP,
dirigivel) tem o mesmo prefixo e comportamentos opostos — /prompt na primeira
devolve 404.

Mutacao: deduzir do prefixo -> vermelho por assercao."
```

---

## Task 2: o modelo Swift decodifica `aceita` — e para de deduzir de prosa

**Files:**
- Modify (no Mac): `beagle-ios/BeagleSuite/Sources/BeagleCore/Fleet/LaneState.swift`
- Create (no Mac): `beagle-ios/BeagleSuite/Tests/BeagleCoreTests/SessaoUsoTests.swift`

**Interfaces:**
- Consumes: o JSON de `/v2/state` com `aceita` (Task 1).
- Produces:
  ```swift
  public enum Aceita: String, Sendable, Codable { case redireciona, enfileira, somenteLeitura }
  // LaneSnapshot ganha: public let aceita: Aceita?
  ```

- [ ] **Step 1: Escrever o teste que falha**

No Mac, crie `Tests/BeagleCoreTests/SessaoUsoTests.swift`:

```swift
import XCTest
@testable import BeagleCore

final class SessaoUsoTests: XCTestCase {

    /// 🚨 `aceita` vem do SERVIDOR. `LaneFamily.of(sid)` devolve `.claude` para claude-1 (tail) e
    /// claude-4 (ACP) — mesmo prefixo, comportamentos opostos. Este teste existe para impedir que
    /// alguém "simplifique" derivando do sid.
    func testAceitaVemDoJSONeNaoDoSid() throws {
        let json = """
        {"lane":"claude-1","kind":"agent_message","confidence":"exact","detail":"x",
         "observed_at_ms":0,"turns":0,"aceita":"somente_leitura"}
        """.data(using: .utf8)!
        let snap = try FleetStateClient.decodificarLane(json)
        XCTAssertEqual(snap.aceita, .somenteLeitura)
        XCTAssertEqual(snap.family, .claude, "a família segue sendo claude — e não decide capacidade")
    }

    func testAceitaAusenteEhNil() throws {
        let json = """
        {"lane":"loom-1","kind":"idle","confidence":"exact","detail":"","observed_at_ms":0,"turns":0}
        """.data(using: .utf8)!
        let snap = try FleetStateClient.decodificarLane(json)
        XCTAssertNil(snap.aceita, "lane sem capacidade declarada não pode virar um chute")
    }
}
```

- [ ] **Step 2: Rodar e ver falhar**

```bash
ssh -o StrictHostKeyChecking=no demetriosagourakis@100.91.184.41 \
  'cd ~/Developer/beagle && swift test --package-path beagle-ios/BeagleSuite --filter SessaoUsoTests 2>&1 | tail -12'
```

Esperado: FAIL — `aceita` não existe em `LaneSnapshot`, e/ou `decodificarLane` não existe.

- [ ] **Step 3: Implementar**

Em `LaneState.swift`, depois de `enum Confidence`:

```swift
/// O que a lane aceita, dito pelo servidor.
///
/// 🚨 NÃO derivar de `sid` nem de `LaneFamily`: `claude-1` (tail) e `claude-4` (ACP) têm o mesmo
/// prefixo e comportamentos opostos. Capacidade é declarada, nunca inferida.
public enum Aceita: String, Sendable, Codable, Equatable {
    case redireciona
    case enfileira
    case somenteLeitura = "somente_leitura"
}
```

Em `LaneSnapshot`, junto dos campos:

```swift
    /// O que esta lane aceita. `nil` = o servidor não declarou; a tela então não oferece gesto.
    public let aceita: Aceita?
```

Se `LaneSnapshot` tiver `init` explícito, acrescente o parâmetro com valor padrão `nil` para não quebrar chamadas. Se houver `CodingKeys`, acrescente `case aceita`. Exponha o helper que o teste usa (ou aponte o teste para o decodificador que já existir — se `FleetStateClient` já tem função de decodificação de lane, **use a existente** em vez de criar outra, e ajuste o teste; duas rotas de decodificação divergem).

- [ ] **Step 4: NÃO tocar em `isAbsent` — e por quê**

`isAbsent` deduz capacidade de prosa (`detail.localizedCaseInsensitiveContains("não existe no
tmux")`), e isso é dívida real: muda a redação no servidor e a tela volta a oferecer ação em lane
que não existe.

**Mas a autoridade dessa frase não é o `loomd`** — é o `LanePoller` do project-cockpit (Node), que
escreve o `detail`. Consertar de verdade exige tocar naquele serviço, o que é **fora do escopo desta
fatia**.

Então: **deixe `isAbsent` exatamente como está.** Não acrescente teste, não acrescente
`XCTExpectFailure`, não mexa. Um teste marcado para falhar sobre algo que decidimos não consertar é
ruído, não cobertura.

Acrescente **apenas** um comentário de uma linha acima dele apontando a dívida:

```swift
    // ⚠️ DÍVIDA: capacidade deduzida de prosa. A frase vem do LanePoller do project-cockpit (Node),
    // não do loomd — consertar exige tocar naquele serviço. Ver o spec desta fatia, §1.
```

Isto é registrado no ledger como dívida conhecida, para o review final triar antes do merge.

- [ ] **Step 5: Rodar e ver passar**

```bash
ssh -o StrictHostKeyChecking=no demetriosagourakis@100.91.184.41 \
  'cd ~/Developer/beagle && swift test --package-path beagle-ios/BeagleSuite 2>&1 | tail -6'
```

Esperado: a suíte inteira verde.

- [ ] **Step 6: Mutação**

No Mac: troque o corpo de `aceita` por derivação de `sid`:

```swift
    public var aceita: Aceita? { sid.hasPrefix("claude") ? .enfileira : .redireciona }
```

`testAceitaVemDoJSONeNaoDoSid` tem de ficar **vermelho por asserção** (`claude-1` viria `.enfileira`
em vez de `.somenteLeitura`). Restaure e confirme o verde.

- [ ] **Step 7: Commit no Mac**

```bash
ssh -o StrictHostKeyChecking=no demetriosagourakis@100.91.184.41 'cd ~/Developer/beagle && \
  git add beagle-ios/BeagleSuite/Sources/BeagleCore/Fleet/LaneState.swift \
          beagle-ios/BeagleSuite/Tests/BeagleCoreTests/SessaoUsoTests.swift && \
  git commit -m "Fleet: aceita vem do servidor, nunca deduzido do sid

LaneFamily.of(sid) da .claude para claude-1 (tail, so leitura) e claude-4 (ACP,
dirigivel) — mesmo prefixo, comportamentos opostos. Capacidade e declarada.

E marquei a divida do isAbsent, que deduz de FRASE EM PORTUGUES: se o servidor
mudar a redacao, ele para de funcionar sem sinal nenhum."'
```

---

## Task 3: o custo — `SessionStep.uso` e `UsoDoTurno`

**Files:**
- Modify (Mac): `BeagleCore/Fleet/SessionStore.swift` (`SessionStep`, `passo(de:)`, `Turno`)
- Modify (Mac): `Tests/BeagleCoreTests/SessaoUsoTests.swift`

**Interfaces:**
- Consumes: `TramaEvent{seq, kind, text, detail, at}` já existente.
- Produces:
  ```swift
  case uso(id: Int, contextoUsado: Int, contextoTeto: Int, usd: Double, at: Date)  // em SessionStep
  public struct UsoDoTurno { public let contextoUsado, contextoTeto: Int; public let usd: Double }
  extension Turno { public var uso: UsoDoTurno? }
  ```

- [ ] **Step 1: Escrever o teste que falha**

```swift
    /// 🚨 MEDIDO nas fixtures do censo ACP: `cost.amount` vem NULO em 15 dos 16 eventos de um
    /// turno — só o último traz o número. Somar "funciona" por ACIDENTE (os outros são zero) e
    /// quebra no dia em que o protocolo preencher os intermediários. O certo é o ÚLTIMO com custo.
    func testUsoDoTurnoPegaOUltimoComCustoNaoASoma() {
        let t0 = Date()
        let passos: [SessionStep] = [
            .prompt(id: 1, text: "faz", at: t0),
            .uso(id: 2, contextoUsado: 31_578, contextoTeto: 1_000_000, usd: 0, at: t0),
            .uso(id: 3, contextoUsado: 36_874, contextoTeto: 1_000_000, usd: 0, at: t0),
            .uso(id: 4, contextoUsado: 38_718, contextoTeto: 1_000_000, usd: 0.3728, at: t0),
        ]
        let turno = Turno.agrupar(passos)[0]
        let uso = try! XCTUnwrap(turno.uso)
        XCTAssertEqual(uso.usd, 0.3728, accuracy: 0.0001, "o último com custo, não a soma")
        XCTAssertEqual(uso.contextoUsado, 38_718, "contexto é absoluto e monotônico: o último vale")
        XCTAssertEqual(uso.contextoTeto, 1_000_000)
    }

    /// O teto varia por agente — 1.000.000 no Claude, 258.400 no Codex via ACP (medido). O rodapé
    /// mostra proporção, então o teto não pode ser constante no código.
    func testTetoDeContextoVemDoEventoNaoDoCodigo() {
        let t0 = Date()
        let passos: [SessionStep] = [
            .prompt(id: 1, text: "x", at: t0),
            .uso(id: 2, contextoUsado: 28_795, contextoTeto: 258_400, usd: 0.01, at: t0),
        ]
        XCTAssertEqual(Turno.agrupar(passos)[0].uso?.contextoTeto, 258_400)
    }

    func testTurnoSemUsoNaoInventaZero() {
        let t0 = Date()
        let passos: [SessionStep] = [.prompt(id: 1, text: "x", at: t0),
                                     .message(id: 2, text: "y", at: t0)]
        XCTAssertNil(Turno.agrupar(passos)[0].uso, "sem evento de uso, o rodapé não mostra custo")
    }

    /// O evento `usage` da trama traz o custo em `detail`, no formato que o loomd escreve:
    /// "contexto 38718/1000000 · USD 0.3728"
    func testPassoDeUsageParseiaODetail() throws {
        let e = TramaEvent(seq: 9, tsMs: 0, lane: "claude-4", kind: "usage",
                           text: nil, detail: "contexto 38718/1000000 · USD 0.3728", diff: nil)
        let passo = try XCTUnwrap(SessionStore.passo(de: e))
        guard case .uso(_, let usado, let teto, let usd, _) = passo else {
            return XCTFail("usage tem de virar .uso, não sumir no default")
        }
        XCTAssertEqual(usado, 38_718); XCTAssertEqual(teto, 1_000_000)
        XCTAssertEqual(usd, 0.3728, accuracy: 0.0001)
    }
```

Se o `init` de `TramaEvent` tiver outra assinatura, ajuste a chamada do teste ao que existe — **não**
mude o `TramaEvent` para caber no teste.

- [ ] **Step 2: Rodar e ver falhar**

```bash
ssh -o StrictHostKeyChecking=no demetriosagourakis@100.91.184.41 \
  'cd ~/Developer/beagle && swift test --package-path beagle-ios/BeagleSuite --filter SessaoUsoTests 2>&1 | tail -14'
```

Esperado: FAIL — `.uso` não existe em `SessionStep`, `Turno.uso` não existe.

- [ ] **Step 3: Implementar**

Em `SessionStep`, junto dos outros casos:

```swift
    /// Custo e janela de contexto. **Não é passo desenhado na conversa** — custo não é fala, e
    /// desenhá-lo na linha do diálogo poluiria o que o operador lê. Vira rodapé do turno.
    case uso(id: Int, contextoUsado: Int, contextoTeto: Int, usd: Double, at: Date)
```

Acrescente `.uso` aos `switch` de `id` e `at` (o compilador vai cobrar — são exaustivos).

Em `passo(de:)`, **antes** do braço que devolve `nil`:

```swift
        case "usage":
            guard let u = Self.uso(de: e.detail ?? "") else { return nil }
            return .uso(id: e.seq, contextoUsado: u.usado, contextoTeto: u.teto, usd: u.usd, at: e.at)
```

E o parser, puro:

```swift
    /// "contexto 38718/1000000 · USD 0.3728" → os três números.
    /// Formato escrito pelo loomd em `from_acp_update`; se ele mudar lá, este teste quebra aqui,
    /// que é o lugar certo para descobrir.
    static func uso(de detail: String) -> (usado: Int, teto: Int, usd: Double)? {
        let nums = detail.split(whereSeparator: { !"0123456789.".contains($0) })
        guard nums.count >= 3,
              let usado = Int(nums[0]), let teto = Int(nums[1]), let usd = Double(nums[2])
        else { return nil }
        return (usado, teto, usd)
    }
```

E em `Turno`:

```swift
    /// O uso do turno. **O último passo com custo**, não a soma — medido: `cost.amount` vem nulo
    /// em 15 dos 16 eventos, e somar funciona por acidente até o protocolo preencher os outros.
    public var uso: UsoDoTurno? {
        var ultimo: UsoDoTurno?
        for p in passos {
            if case .uso(_, let usado, let teto, let usd, _) = p {
                // contexto é absoluto e monotônico: o último sempre vale.
                // custo: só sobrescreve quando o evento realmente trouxe número.
                let usdFinal = usd > 0 ? usd : (ultimo?.usd ?? 0)
                ultimo = UsoDoTurno(contextoUsado: usado, contextoTeto: teto, usd: usdFinal)
            }
        }
        return ultimo
    }
```

```swift
public struct UsoDoTurno: Sendable, Equatable {
    public let contextoUsado: Int
    public let contextoTeto: Int
    public let usd: Double
    public var proporcao: Double {
        contextoTeto > 0 ? Double(contextoUsado) / Double(contextoTeto) : 0
    }
}
```

- [ ] **Step 4: Rodar e ver passar**

```bash
ssh -o StrictHostKeyChecking=no demetriosagourakis@100.91.184.41 \
  'cd ~/Developer/beagle && swift test --package-path beagle-ios/BeagleSuite 2>&1 | tail -6'
```

- [ ] **Step 5: Mutação — e ela precisa de um caso a mais no teste**

A mutação óbvia (somar em vez de pegar o último) dá **o mesmo resultado** com os dados do Step 1,
porque os eventos intermediários trazem custo zero. Uma mutação que não muda o resultado não prova
nada. Então **primeiro acrescente o caso que a torna exercitável** — um `usage` de fechamento **sem
custo depois** de um com custo, que é o que o adaptador de fato emite:

```swift
    /// O último evento de `usage` do turno pode vir SEM custo (fechamento). Se o código
    /// sobrescrever o custo com esse zero, o turno perde o preço que já tinha.
    func testUsoNaoPerdeOCustoQuandoOUltimoEventoVemZerado() {
        let t0 = Date()
        let passos: [SessionStep] = [
            .prompt(id: 1, text: "x", at: t0),
            .uso(id: 2, contextoUsado: 38_000, contextoTeto: 1_000_000, usd: 0.3728, at: t0),
            .uso(id: 3, contextoUsado: 38_718, contextoTeto: 1_000_000, usd: 0, at: t0),
        ]
        let uso = try! XCTUnwrap(Turno.agrupar(passos)[0].uso)
        XCTAssertEqual(uso.usd, 0.3728, accuracy: 0.0001, "o zero de fechamento não apaga o custo")
        XCTAssertEqual(uso.contextoUsado, 38_718, "mas o contexto é o último, sempre")
    }
```

Rode e veja passar. **Agora a mutação:** faça o `usd` sobrescrever sempre, inclusive com zero —

```swift
                ultimo = UsoDoTurno(contextoUsado: usado, contextoTeto: teto, usd: usd)
```

— e confirme que `testUsoNaoPerdeOCustoQuandoOUltimoEventoVemZerado` fica **vermelho por asserção**
(`0.0` em vez de `0.3728`). Restaure e confirme o verde.

Uma segunda mutação, para o contexto: faça o `contextoUsado` guardar o **primeiro** em vez do último
→ `testUsoDoTurnoPegaOUltimoComCustoNaoASoma` fica vermelho.

- [ ] **Step 6: Commit no Mac**

```bash
ssh -o StrictHostKeyChecking=no demetriosagourakis@100.91.184.41 'cd ~/Developer/beagle && \
  git add beagle-ios/BeagleSuite/Sources/BeagleCore/Fleet/SessionStore.swift \
          beagle-ios/BeagleSuite/Tests/BeagleCoreTests/SessaoUsoTests.swift && \
  git commit -m "Sessao: usage deixa de cair no default e vira rodape do turno

MEDIDO nas fixtures: cost.amount vem nulo em 15 dos 16 eventos de um turno.
Somar funciona por ACIDENTE (os outros sao zero) e quebraria no dia em que o
protocolo preencher os intermediarios — o certo e o ultimo COM custo. E o teto
varia por agente (1.000.000 no Claude, 258.400 no Codex), entao vem do evento,
nunca constante no codigo.

Custo nao e fala: nao vira passo desenhado na conversa, vira rodape."'
```

---

## Task 4: o steer para de mentir, e a lane de leitura para de oferecer

**Files:**
- Modify (Mac): `BeagleCore/Fleet/SessionStore.swift` (`rotuloDeGuiar`)
- Modify (Mac): `BeagleWorkbenchKit/Fleet/SessionView.swift` (linha ~245 a caixa, ~136-160 os botões)
- Modify (Mac): `Tests/BeagleCoreTests/SessaoUsoTests.swift`

**Interfaces:**
- Consumes: `Aceita` (Task 2).
- Produces:
  ```swift
  public static func rotuloDeGuiar(_ aceita: Aceita?) -> String?      // nil = não oferecer
  public static func dicaDaCaixa(_ aceita: Aceita?) -> String?        // nil = sem caixa
  ```

- [ ] **Step 1: Escrever o teste que falha**

```swift
    /// 🚨 A caixa diz "guiar o turno em curso" e o botão diz GUIAR. Verdade no codex; MENTIRA na
    /// lane ACP, que enfileira. Mentir no momento da decisão é pior que contar depois — o
    /// operador já agiu.
    func testRotuloDizAVerdadeAntesDoClique() {
        XCTAssertEqual(SessionStore.rotuloDeGuiar(.redireciona), "GUIAR")
        XCTAssertEqual(SessionStore.rotuloDeGuiar(.enfileira), "ENFILEIRAR")
        XCTAssertNil(SessionStore.rotuloDeGuiar(.somenteLeitura), "lane de leitura não oferece gesto")
        XCTAssertNil(SessionStore.rotuloDeGuiar(nil), "sem capacidade declarada, não se oferece nada")
    }

    func testCaixaDeTextoNaoExisteEmLaneDeLeitura() {
        XCTAssertNil(SessionStore.dicaDaCaixa(.somenteLeitura))
        XCTAssertEqual(SessionStore.dicaDaCaixa(.enfileira), "enfileirar para depois deste…")
        XCTAssertEqual(SessionStore.dicaDaCaixa(.redireciona), "guiar o turno em curso…")
    }
```

- [ ] **Step 2: Rodar e ver falhar**

```bash
ssh -o StrictHostKeyChecking=no demetriosagourakis@100.91.184.41 \
  'cd ~/Developer/beagle && swift test --package-path beagle-ios/BeagleSuite --filter testRotulo 2>&1 | tail -8'
```

- [ ] **Step 3: Implementar as funções puras**

```swift
    /// O rótulo do gesto, derivado do que a lane aceita. `nil` = não oferecer botão nenhum.
    public static func rotuloDeGuiar(_ aceita: Aceita?) -> String? {
        switch aceita {
        case .redireciona: return "GUIAR"
        case .enfileira: return "ENFILEIRAR"
        case .somenteLeitura, nil: return nil
        }
    }

    /// A dica da caixa. `nil` = a caixa não existe (não desabilitada: AUSENTE).
    public static func dicaDaCaixa(_ aceita: Aceita?) -> String? {
        switch aceita {
        case .redireciona: return "guiar o turno em curso…"
        case .enfileira: return "enfileirar para depois deste…"
        case .somenteLeitura, nil: return nil
        }
    }
```

- [ ] **Step 4: Ligar na tela**

Em `SessionView.swift`, onde hoje há o `TextField` (linha ~245) e os botões (~136-160):

- o `TextField` e o botão de enviar só existem se `dicaDaCaixa(store.lane.aceita) != nil`;
- o rótulo do botão de guiar vem de `rotuloDeGuiar`;
- em `.somenteLeitura`, no lugar da caixa, a linha:

```swift
    /// Controle morto sem explicação é o defeito que esta casa já pagou para aprender. A lane está
    /// viva e o loomd a lê; o caminho para dirigi-la existe, só não é aqui.
    private var apenasObservada: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye")
            Text("observada pelo transcript — fale com ela pelo terminal")
        }
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.55))
        .padding(.horizontal, 12).padding(.vertical, 10)
    }
```

- [ ] **Step 5: Rodar, construir e ver passar**

```bash
ssh -o StrictHostKeyChecking=no demetriosagourakis@100.91.184.41 'cd ~/Developer/beagle && \
  swift test --package-path beagle-ios/BeagleSuite 2>&1 | tail -6'
```

- [ ] **Step 6: Mutação**

Faça `rotuloDeGuiar` devolver `"GUIAR"` para tudo. `testRotuloDizAVerdadeAntesDoClique` tem de ficar
**vermelho por asserção** — é a mentira que esta tarefa existe para matar. Restaure e confirme verde.

- [ ] **Step 7: Commit no Mac**

```bash
ssh -o StrictHostKeyChecking=no demetriosagourakis@100.91.184.41 'cd ~/Developer/beagle && \
  git add beagle-ios/BeagleSuite/Sources/BeagleCore/Fleet/SessionStore.swift \
          beagle-ios/BeagleSuite/Sources/BeagleWorkbenchKit/Fleet/SessionView.swift \
          beagle-ios/BeagleSuite/Tests/BeagleCoreTests/SessaoUsoTests.swift && \
  git commit -m "Sessao: o botao diz o que VAI acontecer, e lane de leitura nao oferece caixa

GUIAR era verdade no codex e mentira na lane ACP, que enfileira. Mentir no
momento da decisao e pior que contar depois: o operador ja agiu.

E claude-1/2/3 sao tail — POST /prompt devolve 404. A caixa nao fica cinza, ela
NAO EXISTE, e no lugar ha uma linha dizendo o que a lane e e onde falar com ela.
Controle morto sem explicacao e o defeito que esta casa ja pagou para aprender."'
```

---

## Task 5: o acabamento que faz virar "chat"

**Files:**
- Modify (Mac): `BeagleWorkbenchKit/Fleet/SessionView.swift`

**Interfaces:**
- Consumes: `Turno.uso` (Task 3), `UsoDoTurno.proporcao`.
- Produces: nada consumido por outra tarefa (é tela).

- [ ] **Step 1: O rodapé do turno**

Onde o turno é desenhado (por volta da linha 352, onde já se conta ferramentas), acrescente:

```swift
    /// Duração · contexto · custo. O custo vem de `Turno.uso` — a MESMA fonte que o chip da Frota
    /// soma. Dois cálculos independentes divergem, e aí o operador não sabe em qual acreditar.
    @ViewBuilder private func rodape(_ turno: Turno, concluido: Bool) -> some View {
        if let d = turno.duracao(concluido: concluido) {
            HStack(spacing: 10) {
                Text(Self.dur(d))
                if let u = turno.uso {
                    Text("contexto \(Int(u.proporcao * 100))%")
                    if u.usd > 0 { Text(String(format: "US$ %.4f", u.usd)) }
                }
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.white.opacity(0.45))
        }
    }
```

Ajuste a chamada de `duracao(concluido:)` à assinatura real (ela existe e devolve `TimeInterval?`).
**Custo zero não é mostrado** — um "US$ 0,0000" no rodapé de todo turno é ruído que treina o olho
a ignorar a linha.

- [ ] **Step 2: Ferramenta recolhida por padrão**

O passo `.tool` passa a viver dentro de um `DisclosureGroup` fechado, com o cabeçalho mostrando nome
e uma linha de resumo. O arquivo já usa `DisclosureGroup` em outro lugar — **siga o padrão que
existe**, não invente um segundo.

- [ ] **Step 3: O diff com afordância ao lado**

O passo `.diff` já desenha o patch. Acrescente, no cabeçalho do bloco, os botões de aprovar/recusar
**quando o turno tem `pedePermissao`** — reusando o caminho de aprovação que já existe na view (há
`ActionNote` e o fluxo de `approve`). **Não** crie um segundo caminho de aprovação: dois caminhos
para a mesma ação divergem, e este projeto já pagou por isso.

- [ ] **Step 4: Construir e ver na tela**

```bash
ssh -o StrictHostKeyChecking=no demetriosagourakis@100.91.184.41 'cd ~/Developer/beagle && \
  bash beagle-ios/BeagleSuite/scripts/mission-control-app.sh --install 2>&1 | tail -8'
```

O script encerra o app com `quit` limpo (**nunca `pkill -9`**: o app volta sem janela), reabre,
espera a janela, imprime `pid` + `build` e **aborta se o processo for mais velho que o binário**.
**Se ele abortar, pare** — você está olhando um build que não é o seu, e foi assim que três rodadas
de conserto se perderam antes.

- [ ] **Step 5: Commit no Mac**

```bash
ssh -o StrictHostKeyChecking=no demetriosagourakis@100.91.184.41 'cd ~/Developer/beagle && \
  git add beagle-ios/BeagleSuite/Sources/BeagleWorkbenchKit/Fleet/SessionView.swift && \
  git commit -m "Sessao: rodape com custo, ferramenta recolhida, diff com afordancia

O que faz o chat do Claude Code ser bom e nomeavel: ferramenta recolhida e
expansivel, diff inline com aceitar/rejeitar, custo visivel sem pedir. Tudo isso
sobre o que a Sessao JA desenha — ela nao foi reescrita.

Custo zero nao aparece: US$ 0,0000 em todo turno treina o olho a ignorar a linha."'
```

---

## Task 6: o chip da Frota, da mesma fonte

**Files:**
- Modify (Mac): `BeagleWorkbenchKit/Fleet/FrotaView.swift` (`LaneCard`, linha ~443)

**Interfaces:**
- Consumes: `Turno.uso` (Task 3). **Não** recalcula de forma própria.

- [ ] **Step 1: Escrever o teste da concordância**

Em `Tests/BeagleCoreTests/SessaoUsoTests.swift`:

```swift
    /// 🚨 O operador aceitou o custo de dois lugares mostrarem o mesmo número. Eles têm de sair da
    /// MESMA fonte: se o chip recalcular por conta própria, os dois divergem e nenhum é confiável.
    func testAcumuladoDoChipEhASomaDosMesmosTurnos() {
        let t0 = Date()
        let passos: [SessionStep] = [
            .prompt(id: 1, text: "a", at: t0),
            .uso(id: 2, contextoUsado: 100, contextoTeto: 1000, usd: 0.10, at: t0),
            .prompt(id: 3, text: "b", at: t0.addingTimeInterval(1)),
            .uso(id: 4, contextoUsado: 200, contextoTeto: 1000, usd: 0.25, at: t0.addingTimeInterval(1)),
        ]
        let turnos = Turno.agrupar(passos)
        XCTAssertEqual(turnos.count, 2)
        let acumulado = SessionStore.acumulado(turnos)
        let soma = turnos.compactMap { $0.uso?.usd }.reduce(0, +)
        XCTAssertEqual(acumulado, soma, accuracy: 0.0001, "o chip soma os MESMOS Turno.uso")
        XCTAssertEqual(acumulado, 0.35, accuracy: 0.0001)
    }
```

- [ ] **Step 2: Rodar e ver falhar**

```bash
ssh -o StrictHostKeyChecking=no demetriosagourakis@100.91.184.41 \
  'cd ~/Developer/beagle && swift test --package-path beagle-ios/BeagleSuite --filter testAcumulado 2>&1 | tail -8'
```

- [ ] **Step 3: Implementar**

Em `BeagleCore/Fleet/SessionStore.swift`, como `static` de `SessionStore` (é onde `rotuloDeGuiar`
e `dicaDaCaixa` também moram — um só lugar para as funções puras da Sessão):

```swift
    /// O acumulado da lane: soma dos `Turno.uso` — a mesma fonte que o rodapé exibe.
    ///
    /// ⚠️ SUPOSIÇÃO DECLARADA: assume `cost.amount` como custo **do turno**. Se ele for acumulado
    /// da sessão, isto soma duas vezes. Não foi possível verificar — o turno de dois prompts que
    /// responderia isso não executou (credencial da `claude-4` expirada em 11-ago).
    public static func acumulado(_ turnos: [Turno]) -> Double {
        turnos.compactMap { $0.uso?.usd }.reduce(0, +)
    }
```

E no `LaneCard`, ao lado do estado, quando `acumulado > 0`: `US$ x,xx`.

- [ ] **Step 4: Rodar e ver passar**

```bash
ssh -o StrictHostKeyChecking=no demetriosagourakis@100.91.184.41 \
  'cd ~/Developer/beagle && swift test --package-path beagle-ios/BeagleSuite 2>&1 | tail -6'
```

- [ ] **Step 5: Mutação**

Faça `acumulado` recalcular de forma própria (por exemplo, somando `contextoUsado` em vez dos `usd`,
ou pegando só o último turno). O teste de concordância tem de ficar **vermelho por asserção**.

- [ ] **Step 6: Commit no Mac**

```bash
ssh -o StrictHostKeyChecking=no demetriosagourakis@100.91.184.41 'cd ~/Developer/beagle && \
  git add beagle-ios/BeagleSuite/Sources/BeagleCore/Fleet/SessionStore.swift \
          beagle-ios/BeagleSuite/Sources/BeagleWorkbenchKit/Fleet/FrotaView.swift \
          beagle-ios/BeagleSuite/Tests/BeagleCoreTests/SessaoUsoTests.swift && \
  git commit -m "Frota: acumulado no chip, da MESMA fonte que o rodape da Sessao

Ele aceitou o custo de dois lugares mostrarem o mesmo numero — entao eles saem de
uma fonte so. Dois calculos independentes divergem e aí nenhum e confiavel.

Com a suposicao DECLARADA no codigo: assume cost.amount como custo DO TURNO. Se
for acumulado da sessao, soma duas vezes. Nao verificado — o turno que
responderia isso nao executou (credencial da claude-4 expirada)."'
```

---

## Task 7: subir e provar ao vivo

**Files:**
- Modify: `docs/superpowers/specs/2026-08-11-sessao-custo-fala-steer-design.md` (seção de resultado)

- [ ] **Step 1: O loomd de produção com o campo novo**

Sincronize o fonte do `loomd` no pod e reconstrua; então religue o painel `loomd` pelo script que já
existe. **Do t560:**

```bash
export KUBECONFIG=/home/devsounio/.kube/config
cd /home/devsounio/beagle/crates/loomd
for f in src/*.rs; do
  kubectl -n beagle cp "$f" "sounio-workspace-control-0:/tmp/n-$(basename $f)" -c workspace-ssh
done
kubectl -n beagle exec sounio-workspace-control-0 -c workspace-ssh -- \
  su -s /bin/bash openvscode-server -c '
set -e
for f in /tmp/n-*.rs; do cp "$f" "/workspace/.loomd/src/$(basename ${f#/tmp/n-})"; done
export HOME=/workspace/.home/openvscode-server; export PATH="$HOME/.cargo/bin:$PATH"
echo "md5 antes: $(md5sum /workspace/.loomd/target/release/loomd | cut -c1-12)"
cd /workspace/.loomd && cargo build --release -j 6 2>&1 | grep -E "^error" | head -3
echo "md5 depois: $(md5sum /workspace/.loomd/target/release/loomd | cut -c1-12)"
export TMUX_TMPDIR=$HOME/.tmux
tmux respawn-pane -k -t loomd "exec /workspace/.loomd/subir-loomd.sh"
sleep 15; echo "livez: $(curl -s --max-time 8 localhost:4400/livez)"'
```

**Confirme por valor que o md5 mudou.** Se não mudou, o binário é o antigo e nada do que vem depois
prova coisa alguma.

- [ ] **Step 2: O campo `aceita` chega na API**

```bash
kubectl -n beagle exec sounio-workspace-control-0 -c workspace-ssh -- \
  su -s /bin/bash openvscode-server -c '
curl -s --max-time 20 localhost:4400/v2/state | python3 -c "
import json,sys
for l in json.load(sys.stdin).get(\"lanes\",[]):
    print(f\"  {l[\\\"lane\\\"]:<10} aceita={l.get(\\\"aceita\\\")}\")
"'
```

**Critério:** `codex-4`/`loom-1` → `redireciona`; `claude-4` → `enfileira`; `claude-1/2/3` →
`somente_leitura`. Qualquer lane com `aceita` nulo é um caso que a tela não vai oferecer gesto — se
for uma que deveria, o laço em `main()` não a cobriu.

- [ ] **Step 3: Instalar o app e provar na tela**

```bash
ssh -o StrictHostKeyChecking=no demetriosagourakis@100.91.184.41 'cd ~/Developer/beagle && \
  bash beagle-ios/BeagleSuite/scripts/mission-control-app.sh --install 2>&1 | tail -8'
```

**Cinco critérios, e nenhum é opcional:**

1. em `codex-4`, o botão diz **GUIAR**;
2. em `claude-4`, o botão diz **ENFILEIRAR**;
3. em `claude-1`, **não há caixa de prompt** — há a linha "observada pelo transcript";
4. um turno de `claude-4` mostra rodapé com **contexto e USD**;
5. o chip de `claude-4` mostra acumulado, e ele **concorda** com a soma dos rodapés visíveis.

⚠️ O critério 4 depende da `claude-4` **executar turno**, e em 11-ago ela está com **credencial
expirada** — os prompts entram na trama e o turno não roda. Se ainda estiver assim, **reporte
`DONE_WITH_CONCERNS`** dizendo que 1, 2, 3 e 5 foram provados e 4 está bloqueado por credencial.
**Não** declare o 4 provado por inspeção de código.

- [ ] **Step 4: Registrar o resultado no spec e commitar**

Acrescente ao fim do spec uma seção "## Resultado", com o que foi provado e o que ficou bloqueado, e
commite no t560 (branch `reconcile/unify-beagle`).

---

## Notas de risco carregadas do spec

- **Dois lugares com o mesmo número** podem divergir — mitigado por fonte única e pelo teste de
  concordância (Task 6).
- **`cost.amount` pode ser acumulado da sessão.** Suposição declarada no código e no spec. Se for,
  o chip soma duas vezes.
- **O fonte do Mac é o vivo.** Trabalhe em `~/Developer/beagle` no Mac; nunca faça `rsync` do t560
  para o Mac nesta fatia.
- **`isAbsent` deduz de prosa** e continua deduzindo. **Deliberadamente não tocado**: a frase vem do
  `LanePoller` do project-cockpit (Node), não do `loomd`, então consertar é outra fatia. Fica um
  comentário de dívida no código e uma linha no ledger para o review final triar.
