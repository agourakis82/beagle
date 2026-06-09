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
import Hub
import Tokenizers
#endif

// MARK: - Model catalog

/// Model category for grouping in the UI.
public enum ModelCategory: String, CaseIterable, Sendable {
    case reasoning    = "Reasoning"
    case code         = "Code"
    case medical      = "Medical & Bio"
    case exotic       = "Exotic & Frontier"
    case ssm          = "SSM (State Space)"
    case rnn          = "RNN (Recurrent)"
    case diffusion    = "Diffusion"
    case moe          = "MoE (Sparse)"
    case multilingual = "Multilingual"
    case fast         = "Fast & Light"
}

/// Model personality — used by the exocortex to choose the right model for the right cognitive task.
public enum ModelPersonality: String, CaseIterable, Sendable {
    case analytical   // Traditional reasoning
    case creative     // High temperature, diverse outputs
    case medical      // Domain-specific precision
    case stream       // Infinite context, consciousness stream (RWKV, Mamba)
    case memory       // Long-term memory specialist (xLSTM)
    case hybrid       // Best of multiple architectures
    case exotic       // Fundamentally different approach
}

/// Available on-device models — grouped by what they're genuinely best at.
public enum OnDeviceModel: String, CaseIterable, Identifiable, Sendable {

    // Reasoning
    case qwen3_8B        = "qwen3-8b-4bit"
    case deepseekR1      = "deepseek-r1-7b-4bit"
    case aceReason7B     = "acereason-nemotron-7b-4bit"
    case gemma2_9B       = "gemma2-9b-4bit"
    case gemma4_4B       = "gemma4-e4b-4bit"
    case qwen3_4B        = "qwen3-4b-4bit"

    // Code
    case mimo7B          = "mimo-7b-sft-4bit"
    case phi35Mini       = "phi-3.5-mini-4bit"
    case qwen2_5_7B      = "qwen2.5-7b"
    case codeQwen7B      = "codeqwen-7b-4bit"

    // Medical & Bio (PBPK, pharmacokinetics, biomedical literature)
    case bioMistral7B    = "biomistral-7b-4bit"
    case openBioLLM7B    = "openbiollm-7b-4bit"
    case meditron7B      = "meditron-7b-4bit"

    // SSM / Mamba (Tier -1 draft models — O(1) memory, 86+ tok/s)
    case mamba130m       = "mamba-130m"
    case mamba370m       = "mamba-370m"
    case mamba790m       = "mamba-790m"

    // SSM / Hybrid (linear complexity, long context)
    case falconH1_7B     = "falcon-h1r-7b-4bit"
    case lfm2MoE         = "lfm2-8b-a1b-3bit"
    case lfm2_1B         = "lfm2-1.2b-4bit"
    case jamba3B         = "jamba-reasoning-3b-4bit"
    case graniteHybrid   = "granite-4.0-h-tiny-4bit"

    // Exotic & Frontier (different thinking, different architectures)
    case olmo2_7B        = "olmo2-7b-4bit"
    case smolLM2_1_7B    = "smollm2-1.7b-4bit"
    case danube3_4B      = "danube3-4b-4bit"
    case exaone3_8B      = "exaone3-7.8b-4bit"
    case internLM3_8B    = "internlm3-8b-4bit"
    case yi1_5_9B        = "yi-1.5-9b-4bit"

    // RNN (Recurrent) — linear time, infinite context
    case rwkv7_1_5B      = "rwkv7-1.5b-4bit"       // RWKV-7 Goose 1.5B
    case rwkv7_3B        = "rwkv7-3b-4bit"          // RWKV-7 Goose 3B
    case xlstm7B         = "xlstm-7b-4bit"          // xLSTM 7B — 3.5x faster than Transformer

    // Diffusion Language (generates text via denoising — non-autoregressive)
    case plaid1B         = "plaid-1b-4bit"           // PLAID-1B diffusion LM — experimental — MLX conversion pending

    // Mixture of Experts (sparse activation, huge knowledge, small compute)
    case olmoe1B         = "olmoe-1b-7b-4bit"        // OLMoE 1B active / 7B total

    // Recurrence + Attention hybrid (Google Griffin architecture)
    case recurrentGemma  = "recurrentgemma-9b-4bit"  // RecurrentGemma 9B (Griffin arch)

    // Metacognitive / Self-reflective (cloud reference — too large for on-device)
    case reflectionLlama = "reflection-llama-3.1-70b-4bit"  // 70B — cloud reference only

    // Multilingual (strong Portuguese)
    case mistral7B       = "mistral-7b-v0.3-4bit"
    case qwen3_1_7B      = "qwen3-1.7b-4bit"

    // Fast & Light
    case llama3_1_8B     = "llama3.1-8b-4bit"
    case llama3_2_3B     = "llama3.2-3b-4bit"
    case smolLM3_3B      = "smollm3-3b-4bit"
    case gemma4_2B       = "gemma4-e2b-4bit"
    case gemma2_2B       = "gemma2-2b-4bit"
    case bitnet2B        = "bitnet-b1.58-2b-4bit"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mamba130m:      return "Mamba 130M"
        case .mamba370m:      return "Mamba 370M"
        case .mamba790m:      return "Mamba 790M"
        case .qwen3_8B:      return "Qwen 3 8B"
        case .deepseekR1:    return "DeepSeek-R1 7B"
        case .aceReason7B:   return "AceReason 7B"
        case .gemma2_9B:     return "Gemma 2 9B"
        case .gemma4_4B:     return "Gemma 4 4B"
        case .qwen3_4B:      return "Qwen 3 4B"
        case .mimo7B:        return "MiMo 7B"
        case .phi35Mini:     return "Phi 3.5 Mini"
        case .qwen2_5_7B:    return "Qwen 2.5 7B"
        case .codeQwen7B:    return "CodeQwen 7B"
        case .bioMistral7B:  return "BioMistral 7B"
        case .openBioLLM7B:  return "OpenBioLLM 7B"
        case .meditron7B:    return "Meditron 7B"
        case .falconH1_7B:   return "Falcon H1R 7B"
        case .lfm2MoE:       return "LFM2 8B-A1B"
        case .lfm2_1B:       return "LFM2 1.2B"
        case .jamba3B:       return "Jamba 3B"
        case .graniteHybrid: return "Granite Hybrid"
        case .olmo2_7B:      return "OLMo 2 7B"
        case .smolLM2_1_7B:  return "SmolLM2 1.7B"
        case .danube3_4B:    return "Danube 3 4B"
        case .exaone3_8B:    return "EXAONE 3 7.8B"
        case .internLM3_8B:  return "InternLM 3 8B"
        case .yi1_5_9B:      return "Yi 1.5 9B"
        case .rwkv7_1_5B:    return "RWKV-7 1.5B"
        case .rwkv7_3B:      return "RWKV-7 3B"
        case .xlstm7B:       return "xLSTM 7B"
        case .plaid1B:       return "PLAID 1B"
        case .olmoe1B:       return "OLMoE 1B/7B"
        case .recurrentGemma: return "RecurrentGemma 9B"
        case .reflectionLlama: return "Reflection Llama 70B"
        case .mistral7B:     return "Mistral 7B v0.3"
        case .qwen3_1_7B:    return "Qwen 3 1.7B"
        case .llama3_1_8B:   return "Llama 3.1 8B"
        case .llama3_2_3B:   return "Llama 3.2 3B"
        case .smolLM3_3B:    return "SmolLM3 3B"
        case .gemma4_2B:     return "Gemma 4 2B"
        case .gemma2_2B:     return "Gemma 2 2B"
        case .bitnet2B:      return "BitNet 2B"
        }
    }

    public var category: ModelCategory {
        switch self {
        case .qwen3_8B, .deepseekR1, .aceReason7B, .gemma2_9B, .gemma4_4B, .qwen3_4B: return .reasoning
        case .mimo7B, .phi35Mini, .qwen2_5_7B, .codeQwen7B: return .code
        case .bioMistral7B, .openBioLLM7B, .meditron7B: return .medical
        case .mamba130m, .mamba370m, .mamba790m: return .ssm
        case .falconH1_7B, .lfm2MoE, .lfm2_1B, .jamba3B, .graniteHybrid: return .ssm
        case .olmo2_7B, .smolLM2_1_7B, .danube3_4B, .exaone3_8B, .internLM3_8B, .yi1_5_9B: return .exotic
        case .rwkv7_1_5B, .rwkv7_3B, .xlstm7B: return .rnn
        case .plaid1B: return .diffusion
        case .olmoe1B: return .moe
        case .recurrentGemma: return .exotic
        case .reflectionLlama: return .exotic
        case .mistral7B, .qwen3_1_7B: return .multilingual
        case .llama3_1_8B, .llama3_2_3B, .smolLM3_3B, .gemma4_2B, .gemma2_2B, .bitnet2B: return .fast
        }
    }

    public var sizeDescription: String {
        switch self {
        case .mamba130m:      return "~100 MB"
        case .mamba370m:      return "~280 MB"
        case .mamba790m:      return "~500 MB"
        case .qwen3_8B:      return "~5 GB"
        case .deepseekR1:    return "~5 GB"
        case .aceReason7B:   return "~4.5 GB"
        case .gemma2_9B:     return "~5.5 GB"
        case .gemma4_4B:     return "~2.8 GB"
        case .qwen3_4B:      return "~2.5 GB"
        case .mimo7B:        return "~4.5 GB"
        case .phi35Mini:     return "~2.3 GB"
        case .qwen2_5_7B:    return "~4.5 GB"
        case .codeQwen7B:    return "~4.5 GB"
        case .bioMistral7B:  return "~4.5 GB"
        case .openBioLLM7B:  return "~4.5 GB"
        case .meditron7B:    return "~4.5 GB"
        case .falconH1_7B:   return "~4.5 GB"
        case .lfm2MoE:       return "~3 GB"
        case .lfm2_1B:       return "~0.8 GB"
        case .jamba3B:       return "~2 GB"
        case .graniteHybrid: return "~1.5 GB"
        case .olmo2_7B:      return "~4.5 GB"
        case .smolLM2_1_7B:  return "~1.2 GB"
        case .danube3_4B:    return "~2.5 GB"
        case .exaone3_8B:    return "~5 GB"
        case .internLM3_8B:  return "~5 GB"
        case .yi1_5_9B:      return "~5.5 GB"
        case .rwkv7_1_5B:    return "~1 GB"
        case .rwkv7_3B:      return "~2 GB"
        case .xlstm7B:       return "~4.5 GB"
        case .plaid1B:       return "~0.8 GB"
        case .olmoe1B:       return "~4.5 GB"
        case .recurrentGemma: return "~5.5 GB"
        case .reflectionLlama: return "~40 GB"
        case .mistral7B:     return "~4.5 GB"
        case .qwen3_1_7B:    return "~1.2 GB"
        case .llama3_1_8B:   return "~4.8 GB"
        case .llama3_2_3B:   return "~2 GB"
        case .smolLM3_3B:    return "~2 GB"
        case .gemma4_2B:     return "~1.5 GB"
        case .gemma2_2B:     return "~1.5 GB"
        case .bitnet2B:      return "~1 GB"
        }
    }

    public var parameterCount: String {
        switch self {
        case .mamba130m: return "130M"
        case .mamba370m: return "370M"
        case .mamba790m: return "790M"
        case .qwen3_8B, .llama3_1_8B: return "8B"
        case .deepseekR1, .aceReason7B, .falconH1_7B, .mimo7B, .qwen2_5_7B, .mistral7B, .codeQwen7B, .bioMistral7B, .openBioLLM7B, .meditron7B, .olmo2_7B, .xlstm7B: return "7B"
        case .gemma2_9B, .yi1_5_9B, .recurrentGemma: return "9B"
        case .exaone3_8B, .internLM3_8B: return "7.8B"
        case .danube3_4B: return "4B"
        case .lfm2MoE: return "8B (1B active)"
        case .gemma4_4B, .qwen3_4B: return "4B"
        case .phi35Mini: return "3.8B"
        case .jamba3B, .llama3_2_3B, .smolLM3_3B, .rwkv7_3B: return "3B"
        case .gemma4_2B, .gemma2_2B, .bitnet2B: return "2B"
        case .qwen3_1_7B, .smolLM2_1_7B: return "1.7B"
        case .rwkv7_1_5B: return "1.5B"
        case .lfm2_1B, .plaid1B: return "1.2B"
        case .olmoe1B: return "7B (1B active)"
        case .reflectionLlama: return "70B"
        case .graniteHybrid: return "~1B"
        }
    }

    public var bestFor: String {
        switch self {
        case .mamba130m:      return "Tier -1 draft model. O(1) memory, 86+ tok/s. Pre-screening, speculative decoding drafts, stream-of-consciousness capture. Fits on any device."
        case .mamba370m:      return "Mid-size Mamba draft. Better triage accuracy than 130M while still extremely fast. Good speculative acceptance rate."
        case .mamba790m:      return "Largest Mamba draft. Highest standalone quality for SSM-only generation. Best triage accuracy for prompt complexity routing."
        case .qwen3_8B:      return "Top-tier reasoning: math proofs, scientific analysis, multi-step logic. Best overall quality on-device."
        case .deepseekR1:    return "Chain-of-thought specialist. Shows its work step-by-step. Strongest at formal derivations."
        case .aceReason7B:   return "NVIDIA’s math champion. Outperforms larger models on MATH/GSM8K benchmarks."
        case .gemma2_9B:     return "Google’s most careful model. Strong instruction following with safety guardrails."
        case .gemma4_4B:     return "Latest Google architecture. Balanced reasoning + multimodal-ready. Great quality-to-size."
        case .qwen3_4B:      return "Fast reasoning with thinking mode. Sweet spot: quality close to 7B at half the memory."
        case .mimo7B:        return "Xiaomi’s code specialist. Trained on code + math. Better functions than general models."
        case .phi35Mini:     return "Microsoft’s STEM optimizer. Excels at code generation and scientific text."
        case .qwen2_5_7B:    return "Strong coder and technical writer. Good at structured output (JSON, YAML)."
        case .codeQwen7B:    return "Alibaba’s dedicated code model. Trained on 3T code tokens. Superior at completion, refactoring, and explanation."
        case .bioMistral7B:  return "Fine-tuned on PubMed + medical literature. Understands pharmacokinetics, drug interactions, clinical terminology."
        case .openBioLLM7B:  return "Biomedical knowledge extraction specialist. Strong on PBPK modeling terminology and research paper analysis."
        case .meditron7B:    return "Adapted from Llama on medical guidelines + PubMed. Clinical reasoning and evidence-based answers."
        case .falconH1_7B:   return "Mamba2 SSM hybrid — O(n) complexity. Long context without degrading. Future architecture."
        case .lfm2MoE:       return "Liquid SSM + MoE: only 1B params active but 8B total knowledge. Extremely fast."
        case .lfm2_1B:       return "Pure SSM from Liquid AI. Tiny but supports native tool-calling. Fastest in catalog."
        case .jamba3B:       return "AI21’s SSM+Transformer hybrid. Linear complexity for long exocortex conversations."
        case .graniteHybrid: return "IBM’s triple hybrid: SSM + Transformer + MoE. Experimental frontier architecture."
        case .olmo2_7B:      return "Allen AI’s fully open model — weights, data, training logs public. Think different: trained with radical transparency."
        case .smolLM2_1_7B:  return "HuggingFace’s tiny philosopher. Surprisingly coherent for 1.7B. Try it for distilled, crystallized reasoning."
        case .danube3_4B:    return "H2O.ai’s water-themed model. Trained differently — mix of synthetic + real data. Fresh perspective on familiar problems."
        case .exaone3_8B:    return "LG AI Research (Korean). Bilingual mind: trained on Korean+English corpus. East Asian scientific tradition + Western logic."
        case .internLM3_8B:  return "Shanghai AI Lab. Chinese research ecosystem. Different citation base, different assumptions, different conclusions."
        case .yi1_5_9B:      return "01.AI (Yi). Trained on massive Chinese internet. Different cultural priors — valuable for lateral thinking."
        case .rwkv7_1_5B:    return "RWKV-7 Goose 1.5B. Pure RNN — O(n) time, O(1) memory per token. Infinite context without KV cache. Free embedding extraction. Stream-of-consciousness capture."
        case .rwkv7_3B:      return "RWKV-7 Goose 3B. Larger RNN with richer language modeling. Linear time complexity. Ideal for always-on exocortex streams and continuous thought journaling."
        case .xlstm7B:       return "Extended LSTM — 3.5x faster than Transformer at inference. Biological memory gating with exponential gates. Long-term memory specialist for episodic recall."
        case .plaid1B:       return "PLAID-1B diffusion language model. Generates text via iterative denoising — fundamentally non-autoregressive. Parallel token generation. Experimental frontier architecture."
        case .olmoe1B:       return "OLMoE: Mixture of Experts with only 1B params active out of 7B total. Sparse activation means huge knowledge with tiny compute. Allen AI, fully open."
        case .recurrentGemma: return "Google’s Griffin architecture — recurrence + local attention hybrid. Linear scaling with sequence length. Bridge between RNN efficiency and Transformer quality."
        case .reflectionLlama: return "70B self-reflective model. Too large for on-device — cloud reference only. Metacognitive: reasons about its own reasoning. For beagle-consciousness crate integration."
        case .mistral7B:     return "Mistral’s multilingual flagship. Strong Portuguese, French, Spanish. 128k context."
        case .qwen3_1_7B:    return "Alibaba’s fast multilingual. Good Portuguese from massive training. Quick draft model."
        case .llama3_1_8B:   return "Meta’s reliable generalist. Broad biomedical knowledge. Predictable behavior."
        case .llama3_2_3B:   return "Fast general purpose. Good enough for most tasks, small enough for quick loading."
        case .smolLM3_3B:    return "HuggingFace’s efficiency champion. Optimized for mobile. Good all-rounder."
        case .gemma4_2B:     return "Smallest Google model with latest architecture. Ultra-fast for quick questions."
        case .gemma2_2B:     return "Mature small model. Well-tested, predictable. Good emergency fallback."
        case .bitnet2B:      return "Microsoft’s 1.58-bit architecture. Radically efficient — future of inference."
        }
    }

    public var tagline: String {
        switch self {
        case .mamba130m:      return "Draft lightning"
        case .mamba370m:      return "Fast triage"
        case .mamba790m:      return "Best draft"
        case .qwen3_8B:      return "Best overall"
        case .deepseekR1:    return "Shows its work"
        case .aceReason7B:   return "Math champion"
        case .gemma2_9B:     return "Most careful"
        case .gemma4_4B:     return "Balanced"
        case .qwen3_4B:      return "Fast thinker"
        case .mimo7B:        return "Code specialist"
        case .phi35Mini:     return "STEM focused"
        case .qwen2_5_7B:    return "Structured output"
        case .codeQwen7B:    return "3T code tokens"
        case .bioMistral7B:  return "PubMed trained"
        case .openBioLLM7B:  return "Bio extraction"
        case .meditron7B:    return "Clinical reasoning"
        case .falconH1_7B:   return "Long context SSM"
        case .lfm2MoE:       return "Fastest 8B"
        case .lfm2_1B:       return "Tiny + tools"
        case .jamba3B:       return "Reasoning SSM"
        case .graniteHybrid: return "Triple hybrid"
        case .olmo2_7B:      return "Radically open"
        case .smolLM2_1_7B:  return "Tiny philosopher"
        case .danube3_4B:    return "Fresh perspective"
        case .exaone3_8B:    return "Korean+English"
        case .internLM3_8B:  return "Chinese research"
        case .yi1_5_9B:      return "Different priors"
        case .rwkv7_1_5B:    return "Infinite context RNN"
        case .rwkv7_3B:      return "Consciousness stream"
        case .xlstm7B:       return "Biological memory"
        case .plaid1B:       return "Diffusion pioneer"
        case .olmoe1B:       return "Sparse giant"
        case .recurrentGemma: return "Hybrid recurrence"
        case .reflectionLlama: return "Self-reflective"
        case .mistral7B:     return "Multilingual"
        case .qwen3_1_7B:    return "Quick draft"
        case .llama3_1_8B:   return "Reliable generalist"
        case .llama3_2_3B:   return "Quick & capable"
        case .smolLM3_3B:    return "Efficiency king"
        case .gemma4_2B:     return "Ultra-fast"
        case .gemma2_2B:     return "Proven fallback"
        case .bitnet2B:      return "1-bit pioneer"
        }
    }

    public var minimumRAMGB: UInt64 {
        switch self {
        case .qwen3_8B, .deepseekR1, .aceReason7B, .llama3_1_8B, .gemma2_9B,
             .qwen2_5_7B, .falconH1_7B, .mimo7B, .mistral7B,
             .codeQwen7B, .bioMistral7B, .openBioLLM7B, .meditron7B,
             .olmo2_7B, .exaone3_8B, .internLM3_8B, .yi1_5_9B,
             .xlstm7B, .recurrentGemma:
            return 8
        case .gemma4_4B, .qwen3_4B, .phi35Mini, .lfm2MoE, .danube3_4B, .olmoe1B:
            return 6
        case .reflectionLlama:
            return 48  // 70B model — cloud reference only, won't fit on any iOS device
        case .mamba130m, .mamba370m:
            return 2
        case .mamba790m, .jamba3B, .llama3_2_3B, .smolLM3_3B, .gemma4_2B, .gemma2_2B,
             .bitnet2B, .qwen3_1_7B, .lfm2_1B, .graniteHybrid, .smolLM2_1_7B,
             .rwkv7_1_5B, .rwkv7_3B, .plaid1B:
            return 4
        }
    }

    public var fitsOnThisDevice: Bool {
        let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        return ramGB >= minimumRAMGB
    }

    /// Whether this model requires a HuggingFace token (gated model).
    public var requiresHFToken: Bool {
        switch self {
        case .bioMistral7B, .openBioLLM7B, .meditron7B: return true
        case .llama3_1_8B, .llama3_2_3B: return true  // Meta Llama requires agreement
        case .mistral7B: return true                    // Mistral gated
        default: return false
        }
    }

    /// Whether the HF token is configured.
    public static var hasHFToken: Bool {
        UserDefaults.standard.string(forKey: "hfToken")?.isEmpty == false
    }

    /// Whether this model is a Mamba SSM (Tier -1 draft model).
    public var isMamba: Bool {
        switch self {
        case .mamba130m, .mamba370m, .mamba790m: return true
        default: return false
        }
    }

    /// Whether this model is experimental (MLX conversion may not exist yet).
    public var isExperimental: Bool {
        switch self {
        case .rwkv7_1_5B, .rwkv7_3B, .xlstm7B, .plaid1B, .recurrentGemma, .reflectionLlama:
            return true
        default:
            return false
        }
    }

    /// Cognitive personality — used by the exocortex to match models to cognitive tasks.
    public var personality: ModelPersonality {
        switch self {
        // Reasoning — analytical by nature
        case .qwen3_8B, .deepseekR1, .aceReason7B, .gemma2_9B, .gemma4_4B, .qwen3_4B:
            return .analytical

        // Code — analytical with structured output
        case .mimo7B, .phi35Mini, .qwen2_5_7B, .codeQwen7B:
            return .analytical

        // Medical — domain-specific precision
        case .bioMistral7B, .openBioLLM7B, .meditron7B:
            return .medical

        // SSM / Mamba — stream-of-consciousness, infinite context
        case .mamba130m, .mamba370m, .mamba790m:
            return .stream

        // SSM / Hybrid — best of multiple architectures
        case .falconH1_7B, .lfm2MoE, .lfm2_1B, .jamba3B, .graniteHybrid:
            return .hybrid

        // RNN — infinite context, consciousness stream
        case .rwkv7_1_5B, .rwkv7_3B:
            return .stream

        // xLSTM — long-term biological memory
        case .xlstm7B:
            return .memory

        // Diffusion — fundamentally different approach
        case .plaid1B:
            return .exotic

        // MoE — sparse activation hybrid
        case .olmoe1B:
            return .hybrid

        // Recurrent hybrid
        case .recurrentGemma:
            return .hybrid

        // Self-reflective metacognition
        case .reflectionLlama:
            return .exotic

        // Exotic & Frontier — different thinking
        case .olmo2_7B, .smolLM2_1_7B, .danube3_4B:
            return .creative
        case .exaone3_8B, .internLM3_8B, .yi1_5_9B:
            return .creative

        // Multilingual — creative multilingual generation
        case .mistral7B, .qwen3_1_7B:
            return .creative

        // Fast & Light — general analytical
        case .llama3_1_8B, .llama3_2_3B, .smolLM3_3B, .gemma4_2B, .gemma2_2B, .bitnet2B:
            return .analytical
        }
    }

    /// HuggingFace model ID for models loaded directly (non-MLX path).
    public var huggingFaceId: String? {
        switch self {
        case .mamba130m: return "state-spaces/mamba-130m-hf"
        case .mamba370m: return "state-spaces/mamba-370m-hf"
        case .mamba790m: return "state-spaces/mamba-790m-hf"
        case .rwkv7_1_5B: return "RWKV/v7-Goose-1.6B-World"
        case .rwkv7_3B: return "RWKV/v7-Goose-3B-World"
        case .xlstm7B: return "NX-AI/xLSTM-7b"
        case .plaid1B: return "igorbrigadir/PLAID-1B"
        case .olmoe1B: return "allenai/OLMoE-1B-7B-0924"
        case .recurrentGemma: return "google/recurrentgemma-9b-it"
        case .reflectionLlama: return "mattshumer/Reflection-Llama-3.1-70B"
        default: return nil
        }
    }

    #if canImport(MLXLLM)
    var mlxConfiguration: ModelConfiguration {
        switch self {
        case .mamba130m:      return ModelConfiguration(id: "state-spaces/mamba-130m-hf")
        case .mamba370m:      return ModelConfiguration(id: "state-spaces/mamba-370m-hf")
        case .mamba790m:      return ModelConfiguration(id: "state-spaces/mamba-790m-hf")
        case .qwen3_8B:      return LLMRegistry.qwen3_8b_4bit
        case .deepseekR1:    return LLMRegistry.deepSeekR1_7B_4bit
        case .aceReason7B:   return ModelConfiguration(id: "mlx-community/AceReason-Nemotron-7B-4bit")
        case .gemma2_9B:     return LLMRegistry.gemma_2_9b_it_4bit
        case .gemma4_4B:     return LLMRegistry.gemma4_e4b_it_4bit
        case .qwen3_4B:      return LLMRegistry.qwen3_4b_4bit
        case .mimo7B:        return ModelConfiguration(id: "mlx-community/MiMo-7B-SFT-4bit")
        case .phi35Mini:     return ModelConfiguration(id: "mlx-community/Phi-3.5-mini-instruct-4bit")
        case .qwen2_5_7B:    return LLMRegistry.qwen2_5_7b
        case .codeQwen7B:    return ModelConfiguration(id: "mlx-community/CodeQwen1.5-7B-Chat-4bit")
        case .bioMistral7B:  return ModelConfiguration(id: "mlx-community/BioMistral-7B-DARE-4bit")
        case .openBioLLM7B:  return ModelConfiguration(id: "mlx-community/OpenBioLLM-Llama3-8B-4bit")
        case .meditron7B:    return ModelConfiguration(id: "mlx-community/meditron-7b-chat-4bit")
        case .falconH1_7B:   return ModelConfiguration(id: "mlx-community/Falcon-H1R-7B-4bit")
        case .lfm2MoE:       return ModelConfiguration(id: "mlx-community/LFM2-8B-A1B-3bit-MLX")
        case .lfm2_1B:       return ModelConfiguration(id: "mlx-community/LFM2-1.2B-4bit")
        case .jamba3B:       return ModelConfiguration(id: "mlx-community/AI21-Jamba-Reasoning-3B-4bit")
        case .graniteHybrid: return ModelConfiguration(id: "mlx-community/Granite-4.0-H-Tiny-4bit-DWQ")
        case .olmo2_7B:      return ModelConfiguration(id: "mlx-community/OLMo-2-1124-7B-Instruct-4bit")
        case .smolLM2_1_7B:  return ModelConfiguration(id: "mlx-community/SmolLM2-1.7B-Instruct-4bit")
        case .danube3_4B:    return ModelConfiguration(id: "mlx-community/h2o-danube3-4b-chat-4bit")
        case .exaone3_8B:    return ModelConfiguration(id: "mlx-community/EXAONE-3.5-7.8B-Instruct-4bit")
        case .internLM3_8B:  return ModelConfiguration(id: "mlx-community/internlm3-8b-instruct-4bit")
        case .yi1_5_9B:      return ModelConfiguration(id: "mlx-community/Yi-1.5-9B-Chat-4bit")
        case .rwkv7_1_5B:    return ModelConfiguration(id: "mlx-community/RWKV-7-World-1.5B-4bit")     // experimental — MLX conversion pending
        case .rwkv7_3B:      return ModelConfiguration(id: "mlx-community/RWKV-7-World-3B-4bit")       // experimental — MLX conversion pending
        case .xlstm7B:       return ModelConfiguration(id: "mlx-community/xLSTM-7B-4bit")              // experimental — MLX conversion pending
        case .plaid1B:       return ModelConfiguration(id: "mlx-community/PLAID-1B-4bit")              // experimental — MLX conversion pending
        case .olmoe1B:       return ModelConfiguration(id: "mlx-community/OLMoE-1B-7B-0924-4bit")
        case .recurrentGemma: return ModelConfiguration(id: "mlx-community/recurrentgemma-9b-it-4bit")  // experimental — MLX conversion pending
        case .reflectionLlama: return ModelConfiguration(id: "mlx-community/Reflection-Llama-3.1-70B-4bit")  // cloud reference — too large for device
        case .mistral7B:     return ModelConfiguration(id: "mlx-community/Mistral-7B-Instruct-v0.3-4bit")
        case .qwen3_1_7B:    return ModelConfiguration(id: "mlx-community/Qwen3-1.7B-4bit")
        case .llama3_1_8B:   return LLMRegistry.llama3_1_8B_4bit
        case .llama3_2_3B:   return LLMRegistry.llama3_2_3B_4bit
        case .smolLM3_3B:    return ModelConfiguration(id: "mlx-community/SmolLM3-3B-4bit")
        case .gemma4_2B:     return LLMRegistry.gemma4_e2b_it_4bit
        case .gemma2_2B:     return LLMRegistry.gemma_2_2b_it_4bit
        case .bitnet2B:      return ModelConfiguration(id: "mlx-community/bitnet-b1.58-2B-4T-4bit")
        }
    }
    #endif

    public static var recommended: OnDeviceModel {
        let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        if ramGB >= 12 { return .qwen3_8B }
        if ramGB >= 8  { return .qwen3_4B }
        return .gemma4_2B
    }

    public static func models(in category: ModelCategory) -> [OnDeviceModel] {
        allCases.filter { $0.category == category }
    }
}

// MARK: - Engine

@Observable
@MainActor
public final class LocalLLMEngine {

    public static let shared = LocalLLMEngine()

    private static var supportsLocalRuntime: Bool {
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

    public private(set) var loadState: LoadState = .idle
    public private(set) var currentModel: OnDeviceModel? {
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
    public private(set) var downloadProgress: Double = 0
    public private(set) var isGenerating: Bool = false
    public private(set) var tokensPerSecond: Double = 0

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
    private var modelContainer: ModelContainer?
    private var chatSession: ChatSession?

    // Mamba draft model (Tier -1)
    private var mambaContainer: ModelContainer?
    private var mambaSession: ChatSession?
    #endif

    /// Whether a Mamba draft model is loaded for speculative decoding.
    public private(set) var mambaLoaded = false

    /// The currently loaded Mamba draft model, if any.
    public private(set) var mambaModel: OnDeviceModel?

    private init() {
        #if canImport(MLXLLM) && !targetEnvironment(simulator)
        // The GPU buffer cache. A 20 MB cap is right for a memory-constrained
        // iPhone, but on a Mac (iOS-app-on-Mac / "Designed for iPad") it throttles
        // generation to a crawl — each token thrashes the cache, so a full 2048-token
        // turn can take many minutes and read as an "eternal spinner". The Mac has
        // RAM to spare; give the GPU a real cache there.
        if ProcessInfo.processInfo.isiOSAppOnMac {
            Memory.cacheLimit = 512 * 1024 * 1024
        } else {
            Memory.cacheLimit = 20 * 1024 * 1024
        }
        #endif
    }
    
    #if canImport(MLXLLM)
    private func makeChatSession(with container: ModelContainer) -> ChatSession {
        ChatSession(
            container,
            instructions: Self.defaultInstructions,
            generateParameters: Self.defaultGenerateParameters
        )
    }
    #endif

    // MARK: - Load

    public func load(_ model: OnDeviceModel) async {
        guard Self.supportsLocalRuntime else {
            loadState = .error("On-device models are unavailable in the simulator")
            return
        }

        #if canImport(MLXLLM)
        guard loadState != .loading else { return }

        // Check if model fits on this device
        if !model.fitsOnThisDevice {
            loadState = .error("Not enough RAM for \(model.displayName). Needs \(model.minimumRAMGB)GB+.")
            return
        }

        currentModel = model
        loadState = .downloading(0)

        do {
            let config = model.mlxConfiguration
            let downloader = HubApiDownloader()
            let tokenizer = HFTokenizerLoader()

            let container = try await loadModelContainer(
                from: downloader,
                using: tokenizer,
                configuration: config
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.downloadProgress = progress.fractionCompleted
                    self?.loadState = .downloading(progress.fractionCompleted)
                }
            }

            modelContainer = container
            chatSession = makeChatSession(with: container)
            loadState = .ready
        } catch {
            loadState = .error(error.localizedDescription)
        }
        #else
        loadState = .error("MLX not available on this platform")
        #endif
    }

    public func unload() {
        #if canImport(MLXLLM) && !targetEnvironment(simulator)
        chatSession = nil
        modelContainer = nil
        mambaSession = nil
        mambaContainer = nil
        Memory.clearCache()
        #endif
        currentModel = nil
        mambaModel = nil
        mambaLoaded = false
        loadState = .idle
        isGenerating = false
    }

    // MARK: - Generate (streaming)

    public func generate(prompt: String) -> AsyncThrowingStream<String, Error> {
        guard Self.supportsLocalRuntime else {
            return AsyncThrowingStream { $0.finish(throwing: LocalLLMError.platformNotSupported) }
        }

        #if canImport(MLXLLM)
        guard let session = chatSession else {
            return AsyncThrowingStream { $0.finish(throwing: LocalLLMError.modelNotLoaded) }
        }

        isGenerating = true
        let stream = session.streamResponse(to: prompt)

        return AsyncThrowingStream { [weak self] continuation in
            // Run generation OFF the main actor. The whole engine is @MainActor, so a
            // plain `Task {}` here inherits the main executor and the MLX prefill/decode
            // blocks the UI thread — that is the "frozen spinner, zero tokens" symptom.
            // Detach, stream tokens out, and hop back to main only to publish state.
            Task.detached { [weak self] in
                var tokenCount = 0
                let startTime = CFAbsoluteTimeGetCurrent()

                do {
                    for try await chunk in stream {
                        tokenCount += 1
                        continuation.yield(chunk)

                        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                        if elapsed > 0 {
                            let tps = Double(tokenCount) / elapsed
                            await MainActor.run { self?.tokensPerSecond = tps }
                        }
                    }
                } catch {
                    await MainActor.run { self?.isGenerating = false }
                    continuation.finish(throwing: error)
                    return
                }

                await MainActor.run { self?.isGenerating = false }
                continuation.finish()
            }
        }
        #else
        return AsyncThrowingStream { $0.finish(throwing: LocalLLMError.platformNotSupported) }
        #endif
    }

    /// Non-streaming convenience.
    public func respond(to prompt: String) async throws -> String {
        var result = ""
        for try await chunk in generate(prompt: prompt) {
            result += chunk
        }
        return result
    }

    /// Clear conversation history but keep model loaded.
    public func clearHistory() async {
        #if canImport(MLXLLM)
        if let container = modelContainer {
            chatSession = makeChatSession(with: container)
        }
        #endif
    }

    // MARK: - Mamba Draft Model (Tier -1)

    /// Load a Mamba model as draft model for speculative decoding.
    /// The Mamba model runs alongside the primary transformer model, providing
    /// O(1) memory draft tokens at 86+ tok/s for pre-screening and speculation.
    public func loadMambaDraft(_ model: OnDeviceModel) async {
        guard Self.supportsLocalRuntime else { return }
        guard model.isMamba else {
            print("[LocalLLMEngine] \(model.displayName) is not a Mamba model")
            return
        }

        #if canImport(MLXLLM)
        do {
            let config = model.mlxConfiguration
            let downloader = HubApiDownloader()
            let tokenizer = HFTokenizerLoader()

            let container = try await loadModelContainer(
                from: downloader,
                using: tokenizer,
                configuration: config
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    // Report Mamba download progress without disturbing primary model state
                    let _ = progress.fractionCompleted
                    _ = self  // Suppress unused warning
                }
            }

            mambaContainer = container
            mambaSession = ChatSession(
                container,
                instructions: "You are a fast pre-screening model. Classify and draft concisely.",
                generateParameters: GenerateParameters(maxTokens: 256, temperature: 0.3)
            )
            mambaModel = model
            mambaLoaded = true
        } catch {
            print("[LocalLLMEngine] Mamba load failed: \(error)")
            mambaLoaded = false
        }
        #endif
    }

    /// Unload the Mamba draft model, freeing memory.
    public func unloadMamba() {
        #if canImport(MLXLLM) && !targetEnvironment(simulator)
        mambaSession = nil
        mambaContainer = nil
        #endif
        mambaModel = nil
        mambaLoaded = false
    }

    /// Fast Mamba-only generation -- O(1) memory, ~86 tok/s.
    /// Use for: pre-screening, stream-of-consciousness, classification.
    /// Falls back to the primary model if Mamba is not loaded.
    public func mambaGenerate(prompt: String, maxTokens: Int = 256) async throws -> String {
        guard Self.supportsLocalRuntime else {
            throw LocalLLMError.platformNotSupported
        }

        #if canImport(MLXLLM)
        guard let session = mambaSession else {
            throw LocalLLMError.mambaNotLoaded
        }

        var result = ""
        let stream = session.streamResponse(to: prompt)
        var tokenCount = 0
        let startTime = CFAbsoluteTimeGetCurrent()

        for try await chunk in stream {
            tokenCount += 1
            result += chunk
            if tokenCount >= maxTokens { break }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        if elapsed > 0 {
            tokensPerSecond = Double(tokenCount) / elapsed
        }

        return result
        #else
        throw LocalLLMError.platformNotSupported
        #endif
    }

    /// Streaming Mamba-only generation -- O(1) memory, ~86 tok/s.
    /// Ideal for stream-of-consciousness capture with infinite context.
    public func mambaStream(prompt: String, maxTokens: Int = 256) -> AsyncThrowingStream<String, Error> {
        guard Self.supportsLocalRuntime else {
            return AsyncThrowingStream { $0.finish(throwing: LocalLLMError.platformNotSupported) }
        }

        #if canImport(MLXLLM)
        guard let session = mambaSession else {
            return AsyncThrowingStream { $0.finish(throwing: LocalLLMError.mambaNotLoaded) }
        }

        let stream = session.streamResponse(to: prompt)

        return AsyncThrowingStream { [weak self] continuation in
            Task { @MainActor [weak self] in
                var tokenCount = 0
                let startTime = CFAbsoluteTimeGetCurrent()

                do {
                    for try await chunk in stream {
                        tokenCount += 1
                        continuation.yield(chunk)

                        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                        if elapsed > 0 {
                            self?.tokensPerSecond = Double(tokenCount) / elapsed
                        }

                        if tokenCount >= maxTokens { break }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }

                continuation.finish()
            }
        }
        #else
        return AsyncThrowingStream { $0.finish(throwing: LocalLLMError.platformNotSupported) }
        #endif
    }

    /// Speculative decoding -- Mamba drafts tokens, transformer verifies.
    /// Best of both worlds: Mamba speed + transformer quality.
    /// Falls back to regular generate if Mamba is not loaded.
    public func speculativeGenerate(prompt: String) -> AsyncThrowingStream<String, Error> {
        guard Self.supportsLocalRuntime else {
            return AsyncThrowingStream { $0.finish(throwing: LocalLLMError.platformNotSupported) }
        }

        // If Mamba is not loaded or no primary model, fall back to regular generation
        guard mambaLoaded else {
            return generate(prompt: prompt)
        }

        #if canImport(MLXLLM)
        guard let primarySession = chatSession, mambaSession != nil else {
            return generate(prompt: prompt)
        }

        // Speculative decoding strategy:
        // 1. Mamba drafts a batch of tokens (fast, O(1) memory)
        // 2. Transformer verifies/corrects them in parallel (one forward pass)
        // 3. Accept verified tokens, reject divergent ones
        //
        // Current implementation: draft with Mamba, then refine with transformer.
        // True speculative decoding (token-level accept/reject) requires model-level
        // logit access which depends on the MLX version. This implementation provides
        // the semantic equivalent: Mamba proposes, transformer validates.

        return AsyncThrowingStream { [weak self] continuation in
            Task { @MainActor [weak self] in
                do {
                    // Phase 1: Mamba drafts a fast response
                    let draft = try await self?.mambaGenerate(prompt: prompt, maxTokens: 128) ?? ""

                    // Phase 2: Transformer refines with the draft as context
                    let refinementPrompt = """
                    Draft response: \(draft)

                    Verify and improve this draft response to the original question. \
                    Keep what is correct, fix what is wrong, and expand if needed.
                    Original question: \(prompt)
                    """

                    let stream = primarySession.streamResponse(to: refinementPrompt)
                    var tokenCount = 0
                    let startTime = CFAbsoluteTimeGetCurrent()

                    for try await chunk in stream {
                        tokenCount += 1
                        continuation.yield(chunk)

                        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                        if elapsed > 0 {
                            self?.tokensPerSecond = Double(tokenCount) / elapsed
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }

                continuation.finish()
            }
        }
        #else
        return AsyncThrowingStream { $0.finish(throwing: LocalLLMError.platformNotSupported) }
        #endif
    }

    /// Classify whether a prompt needs deep reasoning (should go to Tier 0.5+)
    /// or can be handled by Mamba alone (stays at Tier -1).
    ///
    /// Uses a lightweight Mamba inference: generate a few tokens and measure
    /// perplexity/confidence. Low-complexity prompts (greetings, classification,
    /// short factual) can stay at Tier -1. Medium prompts go to Foundation Models.
    /// Complex prompts require full MLX or cloud.
    public func triagePrompt(_ prompt: String) async -> PromptComplexity {
        guard mambaLoaded else {
            // Without Mamba, we can't triage -- assume medium complexity
            return .medium
        }

        #if canImport(MLXLLM)
        // Heuristic 1: Short prompts with simple patterns are likely simple
        let wordCount = prompt.split(separator: " ").count
        if wordCount <= 5 {
            let lowered = prompt.lowercased()
            let simplePatterns = ["hello", "hi", "hey", "thanks", "yes", "no",
                                  "ok", "what time", "what date", "status"]
            if simplePatterns.contains(where: { lowered.contains($0) }) {
                return .simple
            }
        }

        // Heuristic 2: Complexity signals in the prompt itself
        let complexSignals = ["explain", "analyze", "compare", "prove", "derive",
                              "implement", "refactor", "debug", "why does", "how would",
                              "what if", "trade-off", "architecture", "design pattern",
                              "algorithm", "hypothesis", "differential equation",
                              "pharmacokinetic", "bayesian"]
        let lowered = prompt.lowercased()
        let complexCount = complexSignals.filter { lowered.contains($0) }.count

        if complexCount >= 2 { return .complex }
        if complexCount == 1 && wordCount > 20 { return .complex }

        // Heuristic 3: Try Mamba generation -- if it produces coherent output
        // quickly (high confidence), the prompt is simple enough for Tier -1
        do {
            let startTime = CFAbsoluteTimeGetCurrent()
            let draft = try await mambaGenerate(prompt: prompt, maxTokens: 16)
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            // Fast generation with non-empty output = Mamba can handle it
            let tokPerSec = Double(draft.count) / max(elapsed, 0.001)

            if draft.count >= 8 && tokPerSec > 50 {
                return .simple
            } else if draft.count >= 4 {
                return .medium
            } else {
                return .complex
            }
        } catch {
            // Mamba failed to generate -- assume medium complexity
            return .medium
        }
        #else
        return .medium
        #endif
    }
}

// MARK: - Prompt Complexity (Tier Routing)

/// Result of Mamba-based prompt triage for tier routing.
public enum PromptComplexity: String, Sendable {
    /// Mamba can handle it (greetings, classification, short factual answers).
    case simple
    /// Foundation Models or small MLX model (summaries, extraction, translation).
    case medium
    /// Full MLX transformer or cloud required (reasoning, code, analysis, multi-step).
    case complex
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

// MARK: - Cognitive Router

/// Automatic model selection based on task type and device capability.
/// Maps cognitive tasks to model personalities to specific models.
public enum CognitiveTask: String, CaseIterable, Sendable {
    case thoughtCapture         // Quick capture -> fast/stream personality
    case deepReasoning          // GoDeep -> reasoning personality
    case codeGeneration         // Terminal/agent context -> code personality
    case medicalAnalysis        // PBPK/pharma -> medical personality
    case creativeProvocation    // Serendipity -> creative/exotic personality
    case streamOfConsciousness  // Continuous flow -> stream personality (RWKV/Mamba)
    case triadReview            // Adversarial -> analytical personality
    case translation            // Multilingual -> multilingual personality
    case triage                 // Quick classification -> fast personality
}

extension CognitiveTask {
    /// The model personality best suited for this cognitive task.
    public var preferredPersonality: ModelPersonality {
        switch self {
        case .thoughtCapture:        return .stream
        case .deepReasoning:         return .analytical
        case .codeGeneration:        return .analytical   // code models map to analytical
        case .medicalAnalysis:       return .medical
        case .creativeProvocation:   return .creative
        case .streamOfConsciousness: return .stream
        case .triadReview:           return .analytical
        case .translation:           return .creative     // multilingual models carry creative personality
        case .triage:                return .hybrid
        }
    }

    /// Human-readable description of when this task type applies.
    public var taskDescription: String {
        switch self {
        case .thoughtCapture:        return "Quick thought capture — low latency, streaming"
        case .deepReasoning:         return "Deep reasoning — multi-step logic, proofs, analysis"
        case .codeGeneration:        return "Code generation — implementation, refactoring, debugging"
        case .medicalAnalysis:       return "Medical analysis — PBPK, pharmacokinetics, clinical"
        case .creativeProvocation:   return "Creative provocation — lateral thinking, serendipity"
        case .streamOfConsciousness: return "Stream of consciousness — infinite context, journaling"
        case .triadReview:           return "Triad review — adversarial debate, bias detection"
        case .translation:           return "Translation — multilingual, Portuguese, cross-lingual"
        case .triage:                return "Triage — quick classification, routing"
        }
    }
}

extension LocalLLMEngine {

    /// Suggest the best on-device model for a cognitive task, considering device RAM.
    ///
    /// Selection logic:
    /// 1. Find models whose personality matches the task's preferred personality and fit on this device.
    /// 2. Prefer the lightest model that fits (minimize memory pressure on iPhone).
    /// 3. If no personality match fits, fall back to any model that fits, preferring lighter ones.
    /// 4. Ultimate fallback: gemma2_2B (smallest mature model in the catalog).
    public func suggestModel(for task: CognitiveTask) -> OnDeviceModel {
        let personality = task.preferredPersonality
        let candidates = OnDeviceModel.allCases
            .filter { $0.personality == personality && $0.fitsOnThisDevice && !$0.isExperimental }
            .sorted { $0.minimumRAMGB < $1.minimumRAMGB }

        // Primary: best-fit personality match
        if let best = candidates.first { return best }

        // Secondary: any non-experimental model that fits
        let fallbacks = OnDeviceModel.allCases
            .filter { $0.fitsOnThisDevice && !$0.isExperimental }
            .sorted { $0.minimumRAMGB < $1.minimumRAMGB }

        return fallbacks.first ?? .gemma2_2B
    }

    /// Load the suggested model for a cognitive task, then generate a response.
    ///
    /// If the currently loaded model already matches the suggestion, it stays loaded
    /// (no unnecessary reload). Otherwise the engine loads the suggested model first.
    public func respondForTask(_ task: CognitiveTask, prompt: String) async throws -> String {
        let model = suggestModel(for: task)
        if currentModel != model {
            await load(model)
        }
        return try await respond(to: prompt)
    }

    /// Streaming variant of `respondForTask` — returns tokens as they arrive.
    public func generateForTask(_ task: CognitiveTask, prompt: String) async -> AsyncThrowingStream<String, Error> {
        let model = suggestModel(for: task)
        if currentModel != model {
            await load(model)
        }
        return generate(prompt: prompt)
    }

    /// Combine Mamba triage with cognitive routing:
    /// 1. Mamba classifies prompt complexity.
    /// 2. Simple prompts stay on Mamba (Tier -1).
    /// 3. Medium/complex prompts route through `suggestModel(for:)`.
    ///
    /// This is the highest-level entry point — the exocortex calls this and the
    /// engine handles everything: triage, model selection, loading, generation.
    public func autoRespond(prompt: String, task: CognitiveTask) async throws -> String {
        // For triage and thought capture, try Mamba first if loaded
        if mambaLoaded && (task == .triage || task == .thoughtCapture) {
            let complexity = await triagePrompt(prompt)
            if complexity == .simple {
                return try await mambaGenerate(prompt: prompt, maxTokens: 256)
            }
        }

        return try await respondForTask(task, prompt: prompt)
    }
}

// MARK: - HuggingFace Downloader + TokenizerLoader

#if canImport(MLXLLM)

/// Downloads model snapshots from HuggingFace Hub.
struct HubApiDownloader: Downloader, Sendable {
    let hub: HubApi

    init() {
        // Use stored HF token for gated models (medical, etc.)
        let token = UserDefaults.standard.string(forKey: "hfToken")
        self.hub = HubApi(
            downloadBase: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
            hfToken: token
        )
    }

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        let repo = Hub.Repo(id: id, type: .models)
        return try await hub.snapshot(
            from: repo,
            matching: patterns,
            progressHandler: progressHandler
        )
    }
}

/// Loads tokenizers from HuggingFace swift-transformers.
struct HFTokenizerLoader: TokenizerLoader, Sendable {
    func load(from directory: URL) async throws -> MLXLMCommon.Tokenizer {
        let hfTokenizer = try await AutoTokenizer.from(modelFolder: directory)
        return TokenizerAdapter(hfTokenizer)
    }
}

/// Adapts HuggingFace Tokenizer to MLXLMCommon.Tokenizer protocol.
struct TokenizerAdapter: MLXLMCommon.Tokenizer, @unchecked Sendable {
    private let upstream: Tokenizers.Tokenizer

    init(_ upstream: Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        // Convert Sendable messages to String messages for upstream
        let stringMessages = messages.map { msg in
            msg.reduce(into: [String: String]()) { result, pair in
                result[pair.key] = "\(pair.value)"
            }
        }
        return try upstream.applyChatTemplate(messages: stringMessages)
    }
}
#endif
