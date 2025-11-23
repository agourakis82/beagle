module BeagleLLM

using HTTP
using JSON3

const BEAGLE_CORE_URL = get(ENV, "BEAGLE_CORE_URL", "http://localhost:8080")

"""
    complete(prompt; requires_math=false, requires_high_quality=false, offline_required=false)

Envia o `prompt` para o BEAGLE core server (`/api/llm/complete`) e retorna o texto gerado.

# Arguments
- `prompt::AbstractString`: O prompt a ser completado
- `requires_math::Bool=false`: Se requer matemática pesada
- `requires_high_quality::Bool=false`: Se requer qualidade máxima (usa Grok 4 Heavy se disponível)
- `offline_required::Bool=false`: Se requer processamento offline

# Returns
- `String`: A resposta do LLM

# Example
```julia
using BeagleLLM

answer = BeagleLLM.complete("Explique clearance em PBPK"; requires_math=true)
```
"""
function complete(prompt::AbstractString;
                  requires_math::Bool=false,
                  requires_high_quality::Bool=false,
                  offline_required::Bool=false)

    body = JSON3.write(Dict(
        "prompt" => String(prompt),
        "requires_math" => requires_math,
        "requires_high_quality" => requires_high_quality,
        "offline_required" => offline_required,
    ))

    try
        res = HTTP.post(
            string(BEAGLE_CORE_URL, "/api/llm/complete");
            headers = ["Content-Type" => "application/json"],
            body = body,
            readtimeout = 300.0,  # 5 minutos timeout
        )

        if res.status != 200
            error("BEAGLE LLM error: $(res.status) - $(String(res.body))")
        end

        json = JSON3.read(String(res.body))
        return String(json["text"])
    catch e
        error("BEAGLE LLM connection error: $e")
    end
end

"""
    start_pipeline(question; with_triad=false)

Inicia um pipeline BEAGLE para uma pergunta científica.

# Arguments
- `question::AbstractString`: A pergunta/tópico científico
- `with_triad::Bool=false`: Se deve executar Triad após gerar o draft

# Returns
- `Dict`: Resposta com `run_id` e `status`

# Example
```julia
using BeagleLLM

result = BeagleLLM.start_pipeline("Revisão sistemática sobre scaffolds biológicos"; with_triad=true)
run_id = result["run_id"]
```
"""
function start_pipeline(question::AbstractString; with_triad::Bool=false)
    body = JSON3.write(Dict(
        "question" => String(question),
        "with_triad" => with_triad,
    ))

    try
        res = HTTP.post(
            string(BEAGLE_CORE_URL, "/api/pipeline/start");
            headers = ["Content-Type" => "application/json"],
            body = body,
            readtimeout = 30.0,  # 30 segundos timeout (start é rápido)
        )

        if res.status != 200
            error("BEAGLE Pipeline error: $(res.status) - $(String(res.body))")
        end

        return JSON3.read(String(res.body))
    catch e
        error("BEAGLE Pipeline connection error: $e")
    end
end

"""
    pipeline_status(run_id)

Consulta o status de um pipeline em execução.

# Returns
- `Dict`: Status com `run_id`, `status`, `question`, etc.
"""
function pipeline_status(run_id::AbstractString)
    try
        res = HTTP.get(
            string(BEAGLE_CORE_URL, "/api/pipeline/status/", run_id);
            readtimeout = 10.0,
        )

        if res.status != 200
            error("BEAGLE Pipeline status error: $(res.status) - $(String(res.body))")
        end

        return JSON3.read(String(res.body))
    catch e
        error("BEAGLE Pipeline status connection error: $e")
    end
end

"""
    health()

Verifica a saúde do BEAGLE core server.

# Returns
- `Dict`: Status do servidor
"""
function health()
    try
        res = HTTP.get(
            string(BEAGLE_CORE_URL, "/health");
            readtimeout = 5.0,
        )

        if res.status != 200
            error("BEAGLE Health check error: $(res.status)")
        end

        return JSON3.read(String(res.body))
    catch e
        error("BEAGLE Health check connection error: $e")
    end
end

end # module
