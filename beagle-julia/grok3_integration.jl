#!/usr/bin/env julia

"""
Grok 3 Integration - Valida qualidade do LoRA com Grok 3
"""

module Grok3Integration

using HTTP
using JSON3

const GROK_API_URL = "https://api.x.ai/v1/chat/completions"
const GROK_API_KEY = get(ENV, "GROK_API_KEY", "")

function validate_lora_quality(adapter_path::String, sample_text::String)::Float64
    if isempty(GROK_API_KEY)
        @warn "GROK_API_KEY não configurado. Pulando validação."
        return 0.5  # Score neutro
    end
    
    prompt = """
    Tu és avaliador de qualidade de modelos LoRA.
    
    Adapter LoRA foi treinado para aprender o estilo de escrita de um pesquisador.
    
    Texto de exemplo gerado:
    \"\"\"$sample_text\"\"\"
    
    Avalia a qualidade do LoRA em uma escala de 0-1:
    - 0.0 = Ruim (não aprendeu nada)
    - 0.5 = Médio (aprendeu parcialmente)
    - 1.0 = Excelente (aprendeu perfeitamente o estilo)
    
    Responde APENAS com um número entre 0.0 e 1.0.
    """
    
    try
        body = Dict(
            "model" => "grok-3",
            "messages" => [Dict("role" => "user", "content" => prompt)],
            "temperature" => 0.3,
            "max_tokens" => 10
        )
        
        headers = Dict(
            "Authorization" => "Bearer $GROK_API_KEY",
            "Content-Type" => "application/json"
        )
        
        response = HTTP.post(
            GROK_API_URL,
            headers;
            body=JSON3.write(body),
            readtimeout=30.0
        )
        
        if response.status != 200
            @warn "Grok API retornou status $(response.status)"
            return 0.5
        end
        
        data = JSON3.read(String(response.body))
        score_text = data.choices[1].message.content
        score = parse(Float64, strip(score_text))
        
        @info "✅ Grok 3 validou LoRA: score = $score"
        return score
        
    catch e
        @warn "Erro ao validar com Grok 3: $e"
        return 0.5
    end
end

export validate_lora_quality

end # module

