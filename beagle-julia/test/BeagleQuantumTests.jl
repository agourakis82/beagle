"""
Testes unitários para BeagleQuantum.jl
"""

using Test
using BeagleQuantum

@testset "Hypothesis" begin
    h = Hypothesis("Test hypothesis", ComplexF64(1.0, 0.0))
    @test h.content == "Test hypothesis"
    @test h.probability ≈ 1.0
    @test h.phase ≈ 0.0
    @test h.evidence_count == 0
    
    add_evidence!(h)
    @test h.evidence_count == 1
    @test abs(h.amplitude) > 1.0  # Amplitude aumentou
end

@testset "HypothesisSet" begin
    set = HypothesisSet()
    @test isempty(set.hyps)
    @test !set.is_collapsed
    
    add!(set, "Hypothesis 1")
    add!(set, "Hypothesis 2")
    @test length(set.hyps) == 2
    
    # Probabilidades devem somar ~1.0 após normalização
    total_prob = sum(h -> h.probability, set.hyps)
    @test total_prob ≈ 1.0 atol=1e-10
    
    # Entropia deve ser > 0 para múltiplas hipóteses
    ent = entropy(set)
    @test ent > 0.0
end

@testset "Interference" begin
    set = HypothesisSet()
    add!(set, "Entropia curva é geométrica")
    add!(set, "Entropia curva é consciência celular")
    
    prob_before = set.hyps[2].probability
    
    # Interferência construtiva deve aumentar probabilidade da hipótese relacionada
    interference!(set, "evidência aponta pra consciência celular", 1.5)
    
    prob_after = set.hyps[2].probability
    @test prob_after >= prob_before  # Probabilidade deve aumentar ou manter
    
    # Probabilidades ainda devem somar 1.0
    total_prob = sum(h -> h.probability, set.hyps)
    @test total_prob ≈ 1.0 atol=1e-10
end

@testset "Collapse" begin
    set = HypothesisSet()
    add!(set, "Hypothesis A")
    add!(set, "Hypothesis B")
    add!(set, "Hypothesis C")
    
    # Greedy: deve retornar hipótese com maior probabilidade
    result_greedy = collapse(set, strategy=:greedy)
    @test result_greedy in ["Hypothesis A", "Hypothesis B", "Hypothesis C"]
    @test set.is_collapsed
    
    # Probabilistic: deve retornar alguma hipótese
    set2 = HypothesisSet()
    add!(set2, "Hypothesis X")
    add!(set2, "Hypothesis Y")
    result_prob = collapse(set2, strategy=:probabilistic)
    @test result_prob in ["Hypothesis X", "Hypothesis Y"]
    @test set2.is_collapsed
    
    # Threshold: não colapsa se max_prob < threshold
    set3 = HypothesisSet()
    add!(set3, "Hypothesis Z", ComplexF64(0.1, 0.1))  # Probabilidade baixa
    result_threshold = collapse(set3, strategy=:threshold, threshold=0.5)
    @test result_threshold === nothing  # Não colapsou
    @test !set3.is_collapsed
end

@testset "MeasurementOperator" begin
    set = HypothesisSet()
    add!(set, "Low prob hypothesis", ComplexF64(0.1, 0.1))
    
    operator_low = MeasurementOperator(0.5)
    result = measure(operator_low, set)
    @test result === nothing  # Não colapsou (prob < threshold)
    
    set2 = HypothesisSet()
    add!(set2, "High prob hypothesis", ComplexF64(1.0, 0.0))
    
    operator_high = MeasurementOperator(0.5)
    result2 = measure(operator_high, set2)
    @test result2 !== nothing
    @test result2.content == "High prob hypothesis"
    @test set2.is_collapsed
end

@testset "Normalization" begin
    set = HypothesisSet()
    add!(set, "A", ComplexF64(2.0, 0.0))
    add!(set, "B", ComplexF64(2.0, 0.0))
    
    # Após normalização, probabilidades devem somar 1.0
    total_prob = sum(h -> h.probability, set.hyps)
    @test total_prob ≈ 1.0 atol=1e-10
    
    # Amplitudes devem ser normalizadas também
    for h in set.hyps
        @test abs(h.amplitude) ≈ sqrt(0.5) atol=1e-10
    end
end

@testset "Entropy" begin
    # Entropia máxima quando todas hipóteses têm mesma probabilidade
    set = HypothesisSet()
    add!(set, "A")
    add!(set, "B")
    add!(set, "C")
    add!(set, "D")
    
    ent = entropy(set)
    @test ent > 0.0
    @test ent <= log(4)  # Entropia máxima = log(n)
    
    # Entropia zero quando apenas uma hipótese
    set2 = HypothesisSet()
    add!(set2, "Only one")
    ent2 = entropy(set2)
    @test ent2 ≈ 0.0 atol=1e-10
end

println("\n✅ Todos os testes passaram!")


