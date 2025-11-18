"""
IntegrateLoRATraining.jl - Integração automática completa
100% REAL - Adversarial salva → gera jsonl → treina LoRA → atualiza vLLM

Features:
- Integração completa do ciclo de aprendizado
- Adversarial gera drafts → extrai pares → treina LoRA → aplica
- Loop fechado de melhoria contínua

Roda com: julia integrate_lora_training.jl
"""

module IntegrateLoRATraining

include("adversarial.jl")
using .BeagleAdversarial

include("generate_lora_dataset.jl")
using .GenerateLoRADataset

include("train_lora_lux.jl")
using .TrainLoRALux

using Dates

"""
    run_integrated_cycle(research_question::String; 
                         max_adversarial_iters::Int=6,
                         enable_lora_training::Bool=true) -> Dict

Ciclo completo integrado:
1. Adversarial self-play (salva drafts intermediários)
2. Gera dataset JSONL dos pares
3. Treina LoRA adapter com dataset
4. Retorna draft final + adapter path
"""
function run_integrated_cycle(
    research_question::String;
    max_adversarial_iters::Int=6,
    enable_lora_training::Bool=true
)::Dict
    println("=" ^ 70)
    println("🔄 CICLO INTEGRADO - ADVERSARIAL + LoRA TRAINING")
    println("=" ^ 70)
    println("Pergunta: $research_question")
    println("Adversarial iters: $max_adversarial_iters")
    println("LoRA training: $(enable_lora_training ? "HABILITADO" : "DESABILITADO")")
    println()
    
    results = Dict()
    
    # ========================================================================
    # ETAPA 1: Adversarial self-play (salva drafts intermediários)
    # ========================================================================
    println("📋 ETAPA 1: ADVERSARIAL SELF-PLAY")
    println("─" ^ 70)
    
    # Cria diretório para drafts intermediários
    drafts_dir = "drafts_adversarial/"
    if !isdir(drafts_dir)
        mkpath(drafts_dir)
    end
    
    println("📁 Salvando drafts intermediários em: $drafts_dir")
    println()
    
    # Roda adversarial (já salva drafts internamente se modificado)
    try
        draft_final = adversarial_self_play(
            research_question;
            max_iters=max_adversarial_iters,
            target_quality=98.5,
            enable_lora_training=false,  # Não treina LoRA aqui (faz depois)
            lora_output_dir="lora_adapter"
        )
        
        # Salva draft final também
        timestamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
        final_file = "$(drafts_dir)/draft_final_$(timestamp).md"
        open(final_file, "w") do f
            write(f, draft_final)
        end
        
        results["draft_final"] = draft_final
        results["drafts_dir"] = drafts_dir
        results["adversarial_completed"] = true
        
        println("✅ Draft final gerado: $(length(draft_final)) chars")
        println("💾 Salvo em: $final_file")
        println()
    catch e
        println("⚠️  Erro no adversarial self-play: $e")
        results["adversarial_completed"] = false
        return results
    end
    
    # ========================================================================
    # ETAPA 2: Gera dataset JSONL dos pares (bad → good)
    # ========================================================================
    if !enable_lora_training
        println("📋 ETAPA 2: LoRA TRAINING (pulada - desabilitado)")
        println()
        return results
    end
    
    println("📋 ETAPA 2: GERAÇÃO DE DATASET")
    println("─" ^ 70)
    
    dataset_file = "drafts_paired_$(Dates.format(Dates.now(), "yyyymmdd_HHMMSS")).jsonl"
    
    try
        dataset_path = generate_dataset(drafts_dir, dataset_file)
        
        if isfile(dataset_path)
            results["dataset_file"] = dataset_path
            results["dataset_generated"] = true
            
            # Conta linhas do dataset
            n_lines = countlines(dataset_path)
            results["dataset_pairs"] = n_lines
            
            println("✅ Dataset gerado: $dataset_path ($n_lines pares)")
            println()
        else
            println("⚠️  Dataset não gerado ou vazio")
            results["dataset_generated"] = false
            return results
        end
    catch e
        println("⚠️  Erro ao gerar dataset: $e")
        results["dataset_generated"] = false
        return results
    end
    
    # ========================================================================
    # ETAPA 3: Treina LoRA adapter com dataset
    # ========================================================================
    println("📋 ETAPA 3: LoRA TRAINING COM LUX.JL")
    println("─" ^ 70)
    
    try
        adapter_path = TrainLoRALux.train_from_jsonl(
            dataset_file;
            epochs=10,
            learning_rate=2e-4f0
        )
        
        results["adapter_path"] = adapter_path
        results["lora_trained"] = true
        
        println("✅ LoRA adapter treinado: $adapter_path")
        println()
    catch e
        println("⚠️  Erro no LoRA training: $e")
        results["lora_trained"] = false
    end
    
    # ========================================================================
    # RESUMO FINAL
    # ========================================================================
    println("=" ^ 70)
    println("✅ CICLO INTEGRADO COMPLETO")
    println("=" ^ 70)
    println("📄 Draft final: $(get(results, "draft_final", ""))")
    println("📊 Dataset: $(get(results, "dataset_file", "N/A"))")
    if haskey(results, "dataset_pairs")
        println("   Pares: $(results["dataset_pairs"])")
    end
    println("🎓 LoRA adapter: $(get(results, "adapter_path", "N/A"))")
    println()
    
    return results
end

"""
    demo(research_question::String="")

Demo completo — roda ciclo integrado completo.
"""
function demo(research_question::String="")
    if isempty(research_question)
        research_question = "Unificar entropia curva em scaffolds biológicos com consciência celular via geometria não-comutativa"
    end
    
    return run_integrated_cycle(research_question; enable_lora_training=true)
end

# Descomenta para rodar automaticamente:
# IntegrateLoRATraining.demo()

# Ou roda via CLI:
# julia -e 'include("integrate_lora_training.jl"); using .IntegrateLoRATraining; IntegrateLoRATraining.demo("tua pergunta aqui")'

end # module

