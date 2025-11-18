#!/usr/bin/env julia
"""
Script para rodar Cosmological Alignment completo.
Roda com: julia run_cosmological.jl [hypothesis1] [hypothesis2] ...
"""

include("Cosmological.jl")
using .BeagleCosmological

if length(ARGS) > 0
    # Usa hipóteses fornecidas via CLI
    hypotheses = ARGS
    println("📝 Usando $(length(hypotheses)) hipóteses customizadas:")
    for (i, hyp) in enumerate(hypotheses)
        println("   $i. $(hyp[1:min(80, length(hyp))])...")
    end
    println()
    
    survivors = BeagleCosmological.cosmological_alignment(hypotheses)
    
    # Salva resultado
    timestamp = Dates.format(Dates.now(), "yyyymmdd_HHMMSS")
    filename = "cosmological_survivors_$(timestamp).json"
    
    open(filename, "w") do f
        JSON3.write(f, Dict(
            "survivors" => survivors, 
            "timestamp" => timestamp, 
            "total_analyzed" => length(hypotheses),
            "input_hypotheses" => hypotheses
        ), indent=4)
    end
    
    println("💾 Resultados salvos em: $filename")
else
    # Usa demo padrão
    println("📝 Usando hipóteses de exemplo (demo)")
    println()
    BeagleCosmological.demo()
end

