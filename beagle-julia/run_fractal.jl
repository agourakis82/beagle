#!/usr/bin/env julia
"""
Script para rodar o Fractal Core completo.
Roda com: julia run_fractal.jl [depth] [max_nodes]
"""

include("Fractal.jl")
using .BeagleFractal

# Parse argumentos
depth = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 12
max_nodes = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 1_000_000

println("🚀 Iniciando BEAGLE Fractal Core...")
println("   Depth máximo: $depth")
println("   Max nós: $max_nodes")
println()

# Roda demo
BeagleFractal.demo(target_depth=depth, max_nodes=max_nodes)

