#!/usr/bin/env julia
"""
Script completo — roda Full Orchestrator + Auto-Publish em sequência.
Roda com: julia run_complete_pipeline.jl [research_question]
"""

include("Orchestrator.jl")
using .BeagleFullOrchestrator

include("AutoPublish.jl")
using .BeagleAutoPublish

# Parse argumentos
research_question = length(ARGS) >= 1 ? join(ARGS, " ") : "Unificar entropia curva em scaffolds biológicos com consciência celular via geometria não-comutativa"

println("=" ^ 70)
println("🚀 BEAGLE COMPLETE PIPELINE")
println("=" ^ 70)
println("Pergunta: $research_question")
println()
println("Pipeline:")
println("  1. Full Orchestrator (quantum + cosmo + adversarial + void + fractal)")
println("  2. Auto-Publish (LaTeX + arXiv + Overleaf)")
println()
println("=" ^ 70)
println()

# ETAPA 1: Full Orchestrator
println("📋 ETAPA 1: FULL ORCHESTRATOR")
println("=" ^ 70)
println()

draft = BeagleFullOrchestrator.full_cycle(research_question)

# Encontra arquivo gerado
files = filter(f -> startswith(f, "paper_") && endswith(f, ".md"), readdir())
sort!(files, rev=true)
draft_file = first(files)

println()
println("=" ^ 70)
println("📋 ETAPA 2: AUTO-PUBLISH")
println("=" ^ 70)
println()

# ETAPA 2: Auto-Publish
BeagleAutoPublish.publish_to_arxiv(draft_file)

println()
println("=" ^ 70)
println("✅ PIPELINE COMPLETO FINALIZADO")
println("=" ^ 70)
println("📄 Draft: $draft_file")
println("📦 Tarball arXiv: arxiv_submission/arxiv_submission_*.tar.gz")
println("☁️  Overleaf: (se API key configurada)")
println()
println("🎯 Paper Q1 pronto para submissão!")
println()

