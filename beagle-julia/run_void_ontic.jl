#!/usr/bin/env julia
"""
Script para rodar Void + Ontic Dissolution completo.
Roda com: julia run_void_ontic.jl [custom_state]
"""

include("VoidOntic.jl")
using .BeagleVoidOntic

# Parse argumentos opcionais
custom_state = length(ARGS) >= 1 ? join(ARGS, " ") : ""

println("🚀 Iniciando BEAGLE Void + Ontic Dissolution...")
println()

if !isempty(custom_state)
    println("📝 Usando estado customizado: $custom_state")
    println()
    BeagleVoidOntic.run_void_ontic(custom_state)
else
    println("📝 Usando estado padrão do BEAGLE SINGULARITY")
    println()
    BeagleVoidOntic.run_void_ontic()
end

