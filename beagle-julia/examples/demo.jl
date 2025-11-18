#!/usr/bin/env julia
"""
Demo interativa do BeagleQuantum.jl
Execute: julia --project=.. examples/demo.jl
"""

using Pkg
Pkg.activate("..")
using BeagleQuantum

function main()
    println("\n" * "=" ^ 70)
    println("🔬 BEAGLE QUANTUM - DEMONSTRAÇÃO INTERATIVA")
    println("=" ^ 70)
    println()
    
    # Criar conjunto de hipóteses sobre entropia curva
    set = HypothesisSet()
    
    println("📝 Adicionando hipóteses sobre 'entropia curva'...")
    add!(set, "Entropia curva é uma propriedade geométrica fundamental do espaço-tempo")
    add!(set, "Entropia curva emerge de flutuações quânticas de campo")
    add!(set, "Entropia curva é manifestação de consciência celular emergente")
    add!(set, "Entropia curva é ilusão termodinâmica de sistemas não-equilíbrio")
    add!(set, "Entropia curva é propriedade holográfica de informação quântica")
    add!(set, "Entropia curva é artefato de medição em escalas fractais")
    
    println("✅ $(length(set.hyps)) hipóteses adicionadas")
    println()
    
    # Estado inicial
    println("📊 ESTADO INICIAL (Superposição Quântica):")
    println("-" ^ 70)
    for (i, h) in enumerate(set.hyps)
        println("  [$i] $(h.content[1:min(60, length(h.content))])...")
        println("      Prob: $(round(h.probability, digits=4)) | Fase: $(round(h.phase, digits=3)) | |ψ|: $(round(abs(h.amplitude), digits=3))")
    end
    println("  📈 Entropia de Shannon: $(round(entropy(set), digits=4))")
    println()
    
    # Aplicar evidência 1
    println("⚛️  EVIDÊNCIA 1: 'Dados experimentais mostram correlação com atividade celular'")
    interference!(set, "Dados experimentais mostram correlação com atividade celular", 1.2)
    
    println("\n📊 Estado após evidência 1:")
    println("-" ^ 70)
    sorted_hyps = sort(set.hyps, by=h -> h.probability, rev=true)
    for (i, h) in enumerate(sorted_hyps)
        println("  [$i] $(h.content[1:min(60, length(h.content))])...")
        println("      Prob: $(round(h.probability, digits=4))")
    end
    println("  📈 Entropia: $(round(entropy(set), digits=4))")
    println()
    
    # Aplicar evidência 2
    println("⚛️  EVIDÊNCIA 2: 'Análise geométrica revela estrutura fractal'")
    interference!(set, "Análise geométrica revela estrutura fractal", 1.0)
    
    println("\n📊 Estado após evidência 2:")
    println("-" ^ 70)
    sorted_hyps = sort(set.hyps, by=h -> h.probability, rev=true)
    for (i, h) in enumerate(sorted_hyps)
        println("  [$i] $(h.content[1:min(60, length(h.content))])...")
        println("      Prob: $(round(h.probability, digits=4))")
    end
    println("  📈 Entropia: $(round(entropy(set), digits=4))")
    println()
    
    # Interferência construtiva manual
    println("⚛️  Aplicando interferência construtiva entre top 2 hipóteses...")
    engine = InterferenceEngine(0.5)
    idx1 = findfirst(h -> h.content == sorted_hyps[1].content, set.hyps)
    idx2 = findfirst(h -> h.content == sorted_hyps[2].content, set.hyps)
    if idx1 !== nothing && idx2 !== nothing
        apply_constructive_interference!(engine, set, [idx1, idx2])
    end
    
    println("\n📊 Estado após interferência construtiva:")
    println("-" ^ 70)
    sorted_hyps = sort(set.hyps, by=h -> h.probability, rev=true)
    for (i, h) in enumerate(sorted_hyps)
        println("  [$i] $(h.content[1:min(60, length(h.content))])...")
        println("      Prob: $(round(h.probability, digits=4))")
    end
    println()
    
    # Colapsar superposição
    println("🎯 COLAPSANDO SUPERPOSIÇÃO...")
    println("-" ^ 70)
    
    # Estratégia greedy
    set_greedy = deepcopy(set)
    result_greedy = collapse(set_greedy, strategy=:greedy)
    println("  Greedy: $(result_greedy[1:min(70, length(result_greedy))])...")
    
    # Estratégia probabilística
    set_prob = deepcopy(set)
    result_prob = collapse(set_prob, strategy=:probabilistic)
    println("  Probabilistic: $(result_prob[1:min(70, length(result_prob))])...")
    
    println()
    println("=" ^ 70)
    println("✅ Demonstração concluída!")
    println("=" ^ 70)
    println()
    println("💡 Próximos passos:")
    println("   - Integrar embeddings reais para interferência semântica")
    println("   - Portar multi-agent orchestrator")
    println("   - Implementar LoRA training com Lux.jl + MLX")
    println("   - Adicionar fractal core recursivo")
    println()
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

