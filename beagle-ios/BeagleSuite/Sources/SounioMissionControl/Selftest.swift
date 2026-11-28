#if os(macOS)
import Foundation
import BeagleCore

/// stdout is fully buffered when redirected to a file, so `print` from a GUI process can sit
/// invisible for its whole life. Diagnostics go to stderr, which is not buffered.
private func say(_ m: String) { FileHandle.standardError.write(Data((m + "\n").utf8)) }

/// A startup self-check, printed to stdout. A desktop tool that silently fails to reach its
/// backend is worse than one that says so on line one — this is how "não conecta em nada"
/// becomes a diagnosable sentence instead of a mood.
enum Selftest {
    static func run() async {
        let token = CockpitToken.resolve()
        let ep = FleetEndpoint()
        say("[selftest] host=\(ep.host) scheme=\(ep.scheme)")
        say("[selftest] token: \(token == nil ? "AUSENTE — \(CockpitToken.missingReason)" : "presente (\(token!.count) chars)")")

        guard let req = ep.oficinaRequest() else { say("[selftest] request inválido"); return }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            say("[selftest] GET \(req.url?.path ?? "?") -> HTTP \(code), \(data.count) bytes")
        } catch {
            say("[selftest] GET falhou: \(error.localizedDescription)")
        }
        say("[selftest] loom: \(ep.loomURL()?.absoluteString ?? "?")")

    }
}
#endif
