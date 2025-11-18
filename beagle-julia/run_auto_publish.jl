#!/usr/bin/env julia
"""
Script para auto-publish para arXiv/Overleaf.
Roda com: julia run_auto_publish.jl [draft_file.md]
"""

include("AutoPublish.jl")
using .BeagleAutoPublish

# Parse argumentos
draft_file = length(ARGS) >= 1 ? ARGS[1] : ""

println("🚀 Iniciando BEAGLE Auto-Publish...")
println()

if !isempty(draft_file)
    println("📄 Usando draft: $draft_file")
    println()
    BeagleAutoPublish.auto_publish(draft_file; overleaf_api_key=get(ENV, "OVERLEAF_API_KEY", ""))
else
    println("📄 Procurando último draft automaticamente...")
    println()
    BeagleAutoPublish.demo()
end

