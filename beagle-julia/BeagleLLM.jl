module BeagleLLM

using HTTP
using JSON3

const BEAGLE_CORE_URL = get(ENV, "BEAGLE_CORE_URL", "http://localhost:8080")

"""
    complete(prompt; requires_math=false, requires_high_quality=false, offline_required=false)

Envia o `prompt` para o BEAGLE core server (`/api/llm/complete`) e retorna o texto gerado.
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

    res = HTTP.post(
        string(BEAGLE_CORE_URL, "/api/llm/complete");
        headers = ["Content-Type" => "application/json"],
        body = body,
    )

    if res.status != 200
        error("BEAGLE LLM error: $(res.status)")
    end

    json = JSON3.read(String(res.body))
    return String(json["text"])
end

end # module
