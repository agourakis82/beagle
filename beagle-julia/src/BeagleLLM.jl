# BeagleLLM.jl - Wrapper Julia para BEAGLE LLM API
#
# Uso:
#   using BeagleLLM
#   answer = BeagleLLM.complete("Explique este resultado..."; requires_math=true)

module BeagleLLM

using HTTP
using JSON3

const BEAGLE_CORE_URL = get(ENV, "BEAGLE_CORE_URL", "http://localhost:8080")

"""
    complete(prompt::String; requires_math::Bool=false, requires_high_quality::Bool=false, offline_required::Bool=false)

Completa um prompt usando o BEAGLE LLM API (Grok 3 como Tier 1).

# Arguments
- `prompt::String`: O prompt a ser completado
- `requires_math::Bool=false`: Se requer matemática pesada (usa Tier 2 se disponível)
- `requires_high_quality::Bool=false`: Se requer qualidade máxima (usa Grok 4 Heavy se disponível)
- `offline_required::Bool=false`: Se requer processamento offline (usa Tier 3 se disponível)

# Returns
- `String`: A resposta do LLM

# Example
```julia
using BeagleLLM

answer = BeagleLLM.complete("Explique clearance em PBPK"; requires_math=true)
```
"""
function complete(prompt::String;
                 requires_math::Bool=false,
                 requires_high_quality::Bool=false,
                 offline_required::Bool=false)
    
    body = JSON3.write(Dict(
        "prompt" => prompt,
        "requires_math" => requires_math,
        "requires_high_quality" => requires_high_quality,
        "offline_required" => offline_required,
    ))

    try
        res = HTTP.post(
            string(BEAGLE_CORE_URL, "/api/llm/complete");
            headers = ["Content-Type" => "application/json"],
            body = body,
            readtimeout = 300,  # 5 minutos timeout
        )

        if res.status != 200
            error("BEAGLE LLM error: $(res.status) - $(String(res.body))")
        end

        json = JSON3.read(String(res.body))
        return json["text"]
    catch e
        error("BEAGLE LLM connection error: $e")
    end
end

"""
    chat(messages::Vector{Dict{String, String}}; requires_math::Bool=false, requires_high_quality::Bool=false)

Chat com múltiplas mensagens (futuro - por enquanto usa complete com prompt combinado).
"""
function chat(messages::Vector{Dict{String, String}};
             requires_math::Bool=false,
             requires_high_quality::Bool=false)
    
    # Por enquanto, combina mensagens em prompt único
    prompt = join([m["role"] * ": " * m["content"] for m in messages], "\n\n")
    complete(prompt; requires_math=requires_math, requires_high_quality=requires_high_quality)
end

end # module

