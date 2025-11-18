#!/usr/bin/env julia
"""
Script para rodar Full Orchestrator completo.
Roda com: julia run_full_orchestrator.jl [cycles] [research_question]
"""

include("FullOrchestrator.jl")
using .BeagleFullOrchestrator

# Parse argumentos
cycles = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 1
research_question = length(ARGS) >= 2 ? join(ARGS[2:end], " ") : ""

println("🚀 Iniciando BEAGLE Full Orchestrator...")
println("   Ciclos: $cycles")
if !isempty(research_question)
    println("   Pergunta: $research_question")
end
println()

if cycles > 0
    BeagleFullOrchestrator.demo(cycles, research_question)
else
    # Loop infinito (60 minutos entre ciclos)
    orch = FullOrchestrator(research_question)
    BeagleFullOrchestrator.run_infinite_loop(orch, 60)
end

