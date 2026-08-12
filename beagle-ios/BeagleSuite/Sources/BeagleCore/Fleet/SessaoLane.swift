import Foundation

/// QUAL lane a Sessão mostra — a decisão inteira, isolada da view para poder ser presa em teste.
///
/// 🚨 Existe porque a gaveta de troca de lane "abria e não fazia nada": a cena derivava a lane de
/// `fleet.loomdRoster.first` a cada render, então não havia ONDE guardar a escolha do operador —
/// o clique não tinha para onde ir. Guardar a escolha em `@State` resolve metade; a outra metade
/// é esta regra, que precisa conciliar TRÊS fontes que chegam em tempos diferentes:
///
///   1. a **semente** (`FleetEndpoint.loomdLanes`), que existe antes do primeiro frame;
///   2. o **roster do servidor**, que chega depois — e chegar depois não pode desfazer um clique;
///   3. a **escolha do operador**, que é a única intenção explícita e por isso vence as outras.
///
/// A armadilha que isto mata: semear o estado uma vez com `"loom-1"` e deixar o roster do servidor
/// sobrescrever a tela depois. Por isso a escolha é `String?` — `nil` significa "ele ainda não
/// escolheu, siga o roster", e NÃO "escolheu loom-1". Uma semente concreta em `@State` congelaria
/// a tela numa constante para sempre, que é o defeito espelho.
///
/// Escolha que sai do roster (lane removida no launcher, ou fonte que passou a declarar outra
/// lista) **cai de volta para o roster**: continuar exibindo uma lane que o servidor não lista é
/// exatamente a tela mentindo sobre onde você está, e é o que esta fatia inteira existe para matar.
public enum SessaoLane {

    /// A lane exibida, dadas as três fontes. Pura: sem view, sem rede, sem relógio.
    ///
    /// - Parameters:
    ///   - roster: o roster corrente (de `FleetStateClient.loomdRoster`, que já cai na semente
    ///     quando o servidor não declarou nada — mas aceitamos vazio e caímos de novo aqui,
    ///     porque a função não pode depender de quem a chama ter feito isso).
    ///   - escolha: a última lane que o operador escolheu na gaveta; `nil` = nenhuma escolha.
    public static func exibida(roster: [String], escolha: String?) -> String {
        let base = roster.first ?? FleetEndpoint.loomdLanes.first ?? "loom-1"
        guard let e = escolha, roster.contains(e) else { return base }
        return e
    }
}
