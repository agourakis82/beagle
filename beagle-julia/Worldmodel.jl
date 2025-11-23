#!/usr/bin/env julia
#=
Worldmodel.jl - Modelo de Mundo Simbólico para BEAGLE

Implementa predições baseadas em contexto histórico e padrões simbólicos.
Usa análise de sequências temporais e inferência causal para prever eventos futuros.
=#

module BeagleWorldmodel

using JSON3
using Dates
using Statistics
using LinearAlgebra

export WorldmodelEngine, predict, update_context, get_confidence

struct WorldmodelEngine
    context_history::Vector{Dict{String,Any}}
    max_history::Int
    patterns::Dict{String,Float64}  # Padrões identificados (evento -> probabilidade)
end

function WorldmodelEngine(; max_history::Int=100)
    WorldmodelEngine(
        Vector{Dict{String,Any}}(),
        max_history,
        Dict{String,Float64}()
    )
end

"""
Atualiza o contexto histórico do worldmodel com novos eventos
"""
function update_context(engine::WorldmodelEngine, new_context::Dict{String,Any})
    history = engine.context_history
    push!(history, new_context)
    
    # Mantém apenas os últimos max_history eventos
    if length(history) > engine.max_history
        deleteat!(history, 1:(length(history) - engine.max_history))
    end
    
    # Atualiza padrões baseado na frequência de eventos
    if haskey(new_context, "event_type")
        event_type = new_context["event_type"]
        engine.patterns[event_type] = get(engine.patterns, event_type, 0.0) + 0.1
        # Normaliza probabilidades
        total = sum(values(engine.patterns))
        if total > 0
            for (k, v) in engine.patterns
                engine.patterns[k] = v / total
            end
        end
    end
    
    WorldmodelEngine(history, engine.max_history, engine.patterns)
end

"""
Prediz eventos futuros baseado no contexto histórico
"""
function predict(engine::WorldmodelEngine, horizon::Int=10)::Vector{Dict{String,Any}}
    predictions = Vector{Dict{String,Any}}()
    
    if isempty(engine.context_history)
        # Se não há histórico, retorna predições genéricas
        for i in 1:horizon
            push!(predictions, Dict(
                "step" => i,
                "event" => "unknown",
                "likelihood" => 0.0,
                "confidence" => 0.0
            ))
        end
        return predictions
    end
    
    # Analisa padrões recentes
    recent_contexts = engine.context_history[max(1, end-10):end]
    
    # Extrai tipos de eventos recentes
    recent_events = [get(ctx, "event_type", "unknown") for ctx in recent_contexts]
    
    # Calcula transições de estado
    transitions = Dict{Tuple{String,String},Int}()
    for i in 1:(length(recent_events)-1)
        key = (recent_events[i], recent_events[i+1])
        transitions[key] = get(transitions, key, 0) + 1
    end
    
    # Gera predições baseadas em transições mais prováveis
    last_event = isempty(recent_events) ? "unknown" : recent_events[end]
    
    for step in 1:horizon
        # Encontra transição mais provável a partir do último evento
        next_event = "unknown"
        max_count = 0
        
        for ((from, to), count) in transitions
            if from == last_event && count > max_count
                max_count = count
                next_event = to
            end
        end
        
        # Se não há transição conhecida, usa padrões gerais
        if next_event == "unknown" && !isempty(engine.patterns)
            # Seleciona evento mais provável baseado em padrões
            sorted_patterns = sort(collect(engine.patterns), by=x->x[2], rev=true)
            if !isempty(sorted_patterns)
                next_event = sorted_patterns[1][1]
            end
        end
        
        # Calcula likelihood baseado em frequência
        likelihood = if haskey(engine.patterns, next_event)
            engine.patterns[next_event]
        else
            0.1  # Probabilidade baixa para eventos desconhecidos
        end
        
        # Confidence diminui com horizonte temporal
        confidence = max(0.0, 1.0 - (step - 1) * 0.1)
        
        push!(predictions, Dict(
            "step" => step,
            "event" => next_event,
            "likelihood" => likelihood,
            "confidence" => confidence,
            "timestamp" => Dates.format(now() + Dates.Minute(step), Dates.ISO8601DateTimeFormat)
        ))
        
        # Atualiza last_event para próxima iteração
        last_event = next_event
    end
    
    predictions
end

"""
Calcula confiança geral do modelo baseado na quantidade de histórico
"""
function get_confidence(engine::WorldmodelEngine)::Float64
    if isempty(engine.context_history)
        return 0.0
    end
    
    # Confiança aumenta com mais histórico, até um máximo
    history_confidence = min(1.0, length(engine.context_history) / engine.max_history)
    
    # Confiança também aumenta com mais padrões identificados
    pattern_confidence = min(1.0, length(engine.patterns) / 10.0)
    
    # Média ponderada
    (history_confidence * 0.7 + pattern_confidence * 0.3)
end

end # module BeagleWorldmodel

