import Foundation
import Observation

/// One place that says "the app was asked to go somewhere".
///
/// It exists because the destination and the thing that knows about the URL live in different
/// views: `BeagleCockpitApp` receives `onOpenURL`, while the screen that can actually present the
/// Frota is `BeagleSurface` (iPhone) or the iPad sidebar. Rather than thread a binding through
/// every layer, the URL handler parks a request here and whoever can honour it consumes it.
///
/// This is what a Live Activity, a Shortcut, or a notification tap will use to jump straight to
/// "who needs you" — the whole point of the facho-no-bolso idea.
@MainActor
@Observable
public final class DeepLinkRouter {
    public static let shared = DeepLinkRouter()

    /// Where the app has been asked to go. Cleared by whoever honours it, so a destination is
    /// never presented twice (a re-presented sheet would fight the user's own navigation).
    public private(set) var pending: Destination?

    public enum Destination: String, Sendable, CaseIterable {
        case frota      // Mission Control: who needs you
        case oficina    // dev half: is it green / what broke / where am I
        case work       // the older agent deck

        // OS DOIS QUE FALTAVAM, e sem os quais o widget era enfeite.
        //
        // O ThoughtCaptureWidget emitia `beagle://capture` desde sempre, e este
        // roteador nunca conheceu esse destino: o toque abria o app na tela em que
        // ele estava e a pessoa achava que tinha capturado. Botao morto que PARECE
        // vivo é pior que botao ausente.
        //
        // `falar` nao existia de forma nenhuma. E o gesto mais valioso no plantao:
        // a mao esta ocupada, a tela esta longe dos olhos, e o que se quer é falar
        // — nao navegar ate um lugar onde da para falar.
        case falar      // abre JA OUVINDO, nao numa tela de onde se pode ouvir
        case capturar   // abre direto na captura

        /// Grafias que ja circulam por aí (widget antigo, Atalhos escritos à mão).
        /// Aceitar sinônimo é mais barato que caçar todo emissor — e um destino que
        /// falha em silêncio é justamente o defeito que estamos corrigindo.
        nonisolated static func from(token: String) -> Destination? {
            switch token.lowercased() {
            case "capture", "captura", "capturar": return .capturar
            case "falar", "voz", "voice", "speak": return .falar
            default: return Destination(rawValue: token.lowercased())
            }
        }
    }

    private init() {}

    /// Parse a `beagle://` URL into a destination, or nil if it is not one of ours.
    /// Accepts both `beagle://frota` (host) and `beagle:///frota` (path), because the two forms
    /// are trivially easy to mix up when writing a Shortcut by hand.
    /// `nonisolated` porque é PURO: só lê a URL, não toca estado nenhum do ator.
    /// Sem isto, um Atalho, um teste ou a extensão teriam que saltar para o main
    /// actor só para descobrir se uma URL é nossa.
    nonisolated public static func destination(for url: URL) -> Destination? {
        guard url.scheme == "beagle" else { return nil }
        let token = url.host ?? url.pathComponents.first(where: { $0 != "/" }) ?? ""
        return Destination.from(token: token)
    }

    public func request(_ destination: Destination) { pending = destination }

    /// DEBUG-only: honour a launch argument so a screen can be opened from a script, with no
    /// tap and no system "Abrir com…" prompt (iOS always prompts for URL opens from SpringBoard).
    /// This is how UI screenshots and smoke tests reach a screen deterministically:
    ///
    ///     xcrun simctl launch <udid> dev.sounio.cockpit -beagleOpen frota
    ///
    /// `-key value` launch arguments land in UserDefaults automatically. Release builds ignore
    /// this entirely — it must never be a way into the app on a real device.
    public func applyLaunchArgumentIfPresent() {
        #if DEBUG
        guard
            let raw = UserDefaults.standard.string(forKey: "beagleOpen"),
            let d = Destination(rawValue: raw.lowercased())
        else { return }
        request(d)
        #endif
    }


    /// Take the pending destination, if any, and clear it in the same step.
    public func consume() -> Destination? {
        defer { pending = nil }
        return pending
    }

    /// Handle a URL end-to-end. Returns true when it was ours.
    @discardableResult
    public func open(_ url: URL) -> Bool {
        guard let d = Self.destination(for: url) else { return false }
        request(d)
        return true
    }
}
