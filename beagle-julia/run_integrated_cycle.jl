#!/usr/bin/env julia
"""
Script para rodar ciclo integrado completo (adversarial + dataset + LoRA).
Roda com: julia run_integrated_cycle.jl [research_question]
"""

include("integrate_lora_training.jl")
using .IntegrateLoRATraining

# Parse argumentos
research_question = length(ARGS) >= 1 ? join(ARGS, " ") : ""

if isempty(research_question)
    research_question = "Unificar entropia curva em scaffolds biológicos com consciência celular via geometria não-comutativa"
end

println("🚀 Iniciando BEAGLE Integrated Cycle...")
println("   Pergunta: $research_question")
println()

IntegrateLoRATraining.run_integrated_cycle(
    research_question;
    max_adversarial_iters=6,
    enable_lora_training=true
)

