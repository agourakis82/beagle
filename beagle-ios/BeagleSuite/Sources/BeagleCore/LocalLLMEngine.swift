//
//  LocalLLMEngine.swift
//  BeagleCore
//
//  On-device LLM inference engine backed by MLX Swift.
//  Downloads models from HuggingFace, runs inference on Neural Engine / GPU.
//
//  Tier hierarchy:
//    Tier -1:  Mamba SSM (O(1) memory, 86+ tok/s, draft/triage)
//    Tier 0:   Foundation Models (Apple, quick, sub-second)
//    Tier 0.5: MLX (on-device, deep reasoning, 8-30 tok/s)
//    Tier 1:   Local SGLang (cluster GPU)
//    Tier 2-3: Cloud (Claude, Grok)
//

import Foundation
import Observation

#if canImport(MLXLLM) && canImport(MLXLMCommon)
import MLX
import MLXLLM
import MLXLMCommon
#endif

// MARK: - Engine

@Observable
@MainActor
public final class LocalLLMEngine {

    public static let shared = LocalLLMEngine()

    static var supportsLocalRuntime: Bool {
        #if canImport(MLXLLM) && !targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    #if canImport(MLXLLM)
    private static let defaultInstructions = """
    You are an exocortex — an extension of a researcher's mind working on \
    sovereign supercomputing, PBPK pharmacokinetics, heliobiology, and \
    computational neuroscience. Think deeply. Make cross-domain connections. \
    Challenge assumptions. Be intellectually provocative.
    """
    private static let defaultGenerateParameters = GenerateParameters(maxTokens: 2048, temperature: 0.7)
    #endif

    /// RAM física em GB, medida. O gate de modelo depende disso e divisão
    /// inteira já quase custou a recusa do 14B num aparelho que o comporta.
    nonisolated public static var ramGBMedida: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
    }

    public internal(set) var loadState: LoadState = .idle
    public internal(set) var currentModel: OnDeviceModel? {
        didSet {
            if let model = currentModel {
                UserDefaults.standard.set(model.rawValue, forKey: "lastSelectedModel")
            }
        }
    }

    /// Last model the user selected (persisted across restarts).
    public var lastSelectedModel: OnDeviceModel? {
        guard let raw = UserDefaults.standard.string(forKey: "lastSelectedModel") else { return nil }
        return OnDeviceModel(rawValue: raw)
    }

    // MARK: - Sobreviver ao fechamento do app e à falta de rede

    /// Onde os pesos ficam. **Não** em Caches: o iOS esvazia o diretório de
    /// Caches sob pressão de armazenamento, e o modelo sumiria exatamente no
    /// momento em que ele está sem rede, dentro do hospital.
    nonisolated public static var pesosBase: URL {
        let fm = FileManager.default
        let raiz = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true))
            ?? fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = raiz.appendingPathComponent("modelos-locais", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var url = dir
        var rv = URLResourceValues()
        rv.isExcludedFromBackup = true          // pesos são re-baixáveis; backup não
        try? url.setResourceValues(rv)
        return dir
    }

    /// Move o que já foi baixado para Caches, uma vez. Sem isto, a mudança de
    /// diretório obrigaria a re-baixar vários GB — possivelmente no 5G.
    nonisolated public static func migrarPesosDeCaches() {
        let fm = FileManager.default
        guard let velho = fm.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("models", isDirectory: true),
              fm.fileExists(atPath: velho.path) else { return }
        let novo = pesosBase.appendingPathComponent("models", isDirectory: true)
        if fm.fileExists(atPath: novo.path) { return }
        try? fm.createDirectory(at: novo.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        try? fm.moveItem(at: velho, to: novo)
    }

    /// Os pesos deste modelo estão no aparelho? Config sozinho não basta —
    /// um download interrompido deixa config.json e nenhum peso.
    public func pesosPresentes(_ model: OnDeviceModel) -> Bool {
        // Sem MLX não há runtime local (macOS, por exemplo): a resposta honesta
        // é "não tenho pesos", não uma exceção de compilação.
        #if !canImport(MLXLLM)
        return false
        #else
        let repo = model.mlxConfiguration.name
        let dir = Self.pesosBase.appendingPathComponent("models/\(repo)", isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.appendingPathComponent("config.json").path) else { return false }
        let itens = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        return itens.contains { $0.hasSuffix(".safetensors") || $0.hasSuffix(".npz") }
        #endif
    }

    /// Recarrega o último modelo escolhido, **só** se os pesos já estiverem aqui.
    ///
    /// O engine sempre guardou qual modelo ele escolheu, mas ninguém recarregava
    /// ao abrir o app: `isReady` voltava a false a cada abertura e o caminho
    /// offline caía silenciosamente para a nuvem, que sem rede falha. Este é o
    /// conserto. A checagem de pesos presentes existe para nunca disparar um
    /// download de vários GB no celular sem ele pedir.
    @discardableResult
    public func restaurarUltimoModelo() async -> Bool {
        if isReady { return true }
        if case .loading = loadState { return false }
        Self.migrarPesosDeCaches()
        guard let model = lastSelectedModel, pesosPresentes(model) else { return false }
        await load(model)
        return isReady
    }

    public internal(set) var downloadProgress: Double = 0
    public internal(set) var isGenerating: Bool = false
    public internal(set) var tokensPerSecond: Double = 0

    public enum LoadState: Sendable, Equatable {
        case idle
        case downloading(Double)
        case loading
        case ready
        case error(String)
    }

    public var isReady: Bool { loadState == .ready }
    public var isAvailable: Bool {
        Self.supportsLocalRuntime
    }

    #if canImport(MLXLLM)
    var modelContainer: ModelContainer?
    var chatSession: ChatSession?

    // Mamba draft model (Tier -1)
    var mambaContainer: ModelContainer?
    var mambaSession: ChatSession?
    #endif

    /// Whether a Mamba draft model is loaded for speculative decoding.
    public internal(set) var mambaLoaded = false

    /// The currently loaded Mamba draft model, if any.
    public internal(set) var mambaModel: OnDeviceModel?

    /// Instruções de SISTEMA em vigor na sessão local.
    var instrucoesAtuais: String?

    private init() {
        #if canImport(MLXLLM) && !targetEnvironment(simulator)
        // The GPU buffer cache. A 20 MB cap is right for a memory-constrained
        // iPhone, but on a Mac it throttles generation to a crawl — each token
        // thrashes the cache, so a full 2048-token turn can take many minutes and
        // read as an "eternal spinner". This bites BOTH Mac flavors: iOS-app-on-Mac
        // ("Designed for iPad") AND the native macOS build (where `isiOSAppOnMac` is
        // false). The Mac has RAM to spare; give the GPU a real cache there.
        #if os(macOS)
        Memory.cacheLimit = 512 * 1024 * 1024
        #else
        Memory.cacheLimit = ProcessInfo.processInfo.isiOSAppOnMac ? 512 * 1024 * 1024 : 20 * 1024 * 1024
        #endif
        #endif
    }

    #if canImport(MLXLLM)
    func makeChatSession(with container: ModelContainer, instructions: String? = nil) -> ChatSession {
        ChatSession(
            container,
            instructions: instructions ?? Self.defaultInstructions,
            generateParameters: Self.defaultGenerateParameters
        )
    }
    #endif

    /// Desliga o raciocínio no modelo, quando ele entende o pedido.
    ///
    /// O Qwen3 é híbrido: por padrão emite um bloco <think> que costuma ser
    /// VÁRIAS VEZES maior que a resposta. Filtrar depois resolve o vazamento na
    /// tela, mas não o tempo — e o tempo é o que dói num corredor de hospital.
    /// `/no_think` é o interruptor suave do Qwen; em modelo que não conhece, seria
    /// texto solto no sistema, então só entra quando o modelo é da família.
    public var sufixoSemRaciocinio: String {
        guard let m = currentModel else { return "" }
        return m.rawValue.hasPrefix("qwen3") ? "\n\n/no_think" : ""
    }
}

// MARK: - Errors

public enum LocalLLMError: LocalizedError {
    case modelNotLoaded
    case mambaNotLoaded
    case platformNotSupported

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "No model loaded. Download a model first."
        case .mambaNotLoaded: return "No Mamba draft model loaded. Load a Mamba model first."
        case .platformNotSupported: return "On-device LLM requires iOS/macOS/visionOS."
        }
    }
}
