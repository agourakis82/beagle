# BEAGLE Configuration Module for Julia
# Centralized configuration management respecting SAFE_MODE and BEAGLE_DATA_DIR

module BeagleConfig

export beagle_data_dir, safe_mode, models_dir, logs_dir, papers_drafts_dir, papers_final_dir

"""
    beagle_data_dir() -> String

Retorna o diretório base de dados do BEAGLE.

Ordem de prioridade:
1. Variável de ambiente BEAGLE_DATA_DIR
2. ~/beagle-data (padrão)
"""
function beagle_data_dir()
    if haskey(ENV, "BEAGLE_DATA_DIR")
        return ENV["BEAGLE_DATA_DIR"]
    end
    return joinpath(homedir(), "beagle-data")
end

"""
    safe_mode() -> Bool

Verifica se SAFE_MODE está ativo (default: true).

Quando ativo:
- Nenhuma publicação real será feita (arXiv, Twitter, etc.)
- Ações críticas são logadas mas não executadas
"""
function safe_mode()
    val = get(ENV, "BEAGLE_SAFE_MODE", "true")
    val_lower = lowercase(strip(val))
    return val_lower in ("1", "true", "t", "yes", "y")
end

"""
    models_dir() -> String

Path para modelos LLM.
"""
function models_dir()
    return joinpath(beagle_data_dir(), "models")
end

"""
    logs_dir() -> String

Path para logs.
"""
function logs_dir()
    return joinpath(beagle_data_dir(), "logs")
end

"""
    papers_drafts_dir() -> String

Path para drafts de papers.
"""
function papers_drafts_dir()
    return joinpath(beagle_data_dir(), "papers", "drafts")
end

"""
    papers_final_dir() -> String

Path para papers finais.
"""
function papers_final_dir()
    return joinpath(beagle_data_dir(), "papers", "final")
end

"""
    publish_mode() -> Symbol

Retorna o modo de publicação atual.

Valores:
- :dry (default) - nunca chama API real
- :manual - exige confirmação humana
- :auto - permite publicação automática (só se safe_mode() == false)
"""
function publish_mode()
    mode_str = lowercase(strip(get(ENV, "BEAGLE_PUBLISH_MODE", "dry")))
    if mode_str == "auto"
        return :auto
    elseif mode_str == "manual"
        return :manual
    else
        return :dry
    end
end

"""
    can_publish_real() -> Bool

Verifica se publicação real é permitida.

Retorna true apenas se:
- safe_mode() == false
- E publish_mode() == :auto
"""
function can_publish_real()
    return !safe_mode() && publish_mode() == :auto
end

end # module

