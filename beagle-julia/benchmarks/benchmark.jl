#!/usr/bin/env julia
"""
Benchmark de performance do BeagleQuantum.jl
Compara operações básicas com diferentes tamanhos de conjunto.
"""

using Pkg
Pkg.activate("..")
using BeagleQuantum
using BenchmarkTools
using Statistics

function benchmark_add(n_hyps::Int)
    set = HypothesisSet()
    @btime begin
        for i in 1:$n_hyps
            add!(set, "Hypothesis $i")
        end
    end
end

function benchmark_interference(n_hyps::Int)
    set = HypothesisSet()
    for i in 1:n_hyps
        add!(set, "Hypothesis $i about entropy and quantum mechanics")
    end
    
    @btime interference!($set, "evidence about entropy", 1.0)
end

function benchmark_collapse(n_hyps::Int)
    set = HypothesisSet()
    for i in 1:n_hyps
        add!(set, "Hypothesis $i")
    end
    
    @btime collapse($set, strategy=:probabilistic)
end

function benchmark_entropy(n_hyps::Int)
    set = HypothesisSet()
    for i in 1:n_hyps
        add!(set, "Hypothesis $i")
    end
    
    @btime entropy($set)
end

function main()
    println("\n" * "=" ^ 70)
    println("⚡ BEAGLE QUANTUM - BENCHMARKS DE PERFORMANCE")
    println("=" ^ 70)
    println()
    
    sizes = [10, 100, 1000, 10000]
    
    println("📊 Benchmark: add!() - Adicionar hipóteses")
    println("-" ^ 70)
    for n in sizes
        print("  n=$n: ")
        benchmark_add(n)
    end
    println()
    
    println("📊 Benchmark: interference!() - Aplicar interferência")
    println("-" ^ 70)
    for n in sizes
        print("  n=$n: ")
        benchmark_interference(n)
    end
    println()
    
    println("📊 Benchmark: collapse() - Colapsar superposição")
    println("-" ^ 70)
    for n in sizes
        print("  n=$n: ")
        benchmark_collapse(n)
    end
    println()
    
    println("📊 Benchmark: entropy() - Calcular entropia")
    println("-" ^ 70)
    for n in sizes
        print("  n=$n: ")
        benchmark_entropy(n)
    end
    println()
    
    println("=" ^ 70)
    println("✅ Benchmarks concluídos!")
    println("=" ^ 70)
    println()
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end


